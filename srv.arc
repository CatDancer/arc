; HTTP Server.

; could make form fields that know their value type because of
; gensymed names, and so the receiving fn gets args that are not
; strings but parsed values.

; if you want to be able to ^C the server, set breaksrv* to t

(= arcdir* "arc/" logdir* "arc/logs/" quitsrv* nil breaksrv* nil) 

(def serve ((o port 8080))
  (wipe quitsrv*)
  (ensure-srvdirs)
  (w/socket s port
    (prn "ready to serve port " port)
    (= currsock* s)
    (until quitsrv*
      (if breaksrv* 
          (handle-request s)
          (errsafe (handle-request s)))))
  (prn "quit server"))

(def serve1 ((o port 8080))
  (w/socket s port (handle-request s)))

(def ensure-srvdirs ()
  (ensure-dir arcdir*)
  (ensure-dir logdir*))

(= srv-noisy* nil)

; http requests currently capped at 2 meg by socket-accept

; should threads process requests one at a time? no, then
; a browser that's slow consuming the data could hang the
; whole server.

; wait for a connection from a browser and start a thread
; to handle it. also arrange to kill that thread if it
; has not completed in threadlife* seconds.

(= srvthreads* nil threadlimit* 50 threadlife* 30)

; Could auto-throttle ips, e.g. if one has more than x% of recent requests.

(= requests* 0 requests/ip* (table) throttle-ips* (table) throttle-time* 30)

(def handle-request (s (o life threadlife*))
  (if (len< (pull dead srvthreads*) threadlimit*)
      (let (i o ip) (socket-accept s)
        (++ requests*)
        (= (requests/ip* ip) (+ 1 (or (requests/ip* ip) 0)))
        (let th (thread 
                  (if (throttle-ips* ip) (sleep (rand throttle-time*)))
                  (handle-request-thread i o ip))
          (push th srvthreads*)
          (thread (sleep life)
                  (unless (dead th) (prn "srv thread took too long"))
                  (break-thread th)
                  (close i o))))
      (sleep .2)))

(def handle-request-thread (i o ip)
  (with (nls 0 lines nil line nil responded nil)
    (after
      (whilet c (unless responded (readc i))
        (if srv-noisy* (pr c))
        (if (is c #\newline)
            (if (is (++ nls) 2) 
                (let (type op args n cooks) (parseheader (rev lines))
                  (srvlog 'srv ip type op cooks)
                  (case type
                    get  (respond o op args cooks ip)
                    post (handle-post i o op n cooks ip)
                         (respond-err o "Unknown request: " (car lines)))
                  (assert responded))
                (do (push (string (rev line)) lines)
                    (wipe line)))
            (unless (is c #\return)
              (push c line)
              (= nls 0))))
      (close i o)))
  (harvest-fnids))

; Could ignore return chars (which come from textarea fields) here by
; (unless (is c #\return) (push c line))

(def handle-post (i o op n cooks ip)
  (if srv-noisy* (pr "Post Contents: "))
  (if (no n)
      (respond-err o "Post request without Content-Length.")
      (let line nil
        (whilet c (and (> n 0) (readc i))
          (if srv-noisy* (pr c))
          (-- n)
          (push c line)) 
        (if srv-noisy* (pr "\n\n"))
        (respond o op (parseargs (string (rev line))) cooks ip))))

(def ok-response (content-type)
  (string "HTTP/1.0 200 OK
Content-Type: " content-type "
Connection: close"))

(= header* (ok-response "text/html; charset=utf-8"))

(= rdheader* "HTTP/1.0 302 Moved")

(= srvops* (table) redirector* (table) optimes* (table))

(def save-optime (name elapsed)
  (unless (optimes* name) (= (optimes* name) (queue)))
  (enq-limit elapsed (optimes* name) 1000))

; For ops that want to add their own headers.  They must thus remember 
; to prn a blank line before anything meant to be part of the page.

(mac defop-raw (name parms . body)
  (w/uniq t1
    `(= (srvops* ',name) 
        (fn ,parms 
          (let ,t1 (msec)
            (do1 (do ,@body)
                 (save-optime ',name (- (msec) ,t1))))))))

(mac defopr-raw (name parms . body)
  `(= (redirector* ',name) t
      (srvops* ',name)     (fn ,parms ,@body)))

(mac defop (name parm . body)
  (w/uniq gs
    `(defop-raw ,name (,gs ,parm) 
       (w/stdout ,gs (prn) ,@body))))

; Defines op as a redirector.  Its retval is new location.

(mac defopr (name parm . body)
  (w/uniq gs
    `(do (assert (redirector* ',name))
         (defop-raw ,name (,gs ,parm)
           ,@body))))

;(mac testop (name . args) `((srvops* ',name) ,@args))

(deftem request
  args  nil
  cooks nil
  ip    nil)

(= unknown-msg* "Unknown operator.")

(def static-path (op)
  (string "static/" op))

(def respond (str op args cooks ip)
  (w/stdout str
    (aif (srvops* op)
          (let req (inst 'request 'args args 'cooks cooks 'ip ip)
            (if (redirector* op)
                (do (prn rdheader*)
                    (prn "Location: " (it str req))
                    (prn))
                (do (prn header*)
                    (it str req))))
         (static-filetype op)
          (do (prn (ok-response it))
              (prn)
              (w/infile i (static-path op)
                (whilet b (readb i)
                  (writeb b str))))
          (respond-err str unknown-msg*))))

(def gifname (sym)
  (let str (string sym)
    (and (endmatch ".gif" str) (~find #\/ str))))

; Exclude arc, or anyone can see source.  Need to use a separate dir.

(def static-filetype (sym)
  (let fname (string sym)
    (and (~find #\/ fname)
         (case (last (check (tokens fname #\.) ~single))
           "gif"  'image/gif
           "jpg"  'image/jpg
           "css"  'text/css
           "txt"  'text/plain
           "html" '|text/html; charset=utf-8|
           ))))

(def respond-err (str msg . args)
  (w/stdout str
    (prn header*)
    (prn)
    (apply pr msg args)))

(def parseheader (lines)
  (let (type op args) (parseurl (car lines))
    (list type
          op
          args
          (and (is type 'post)
               (some (fn (s)
                       (and (begins s "Content-Length:")
                            (coerce (cadr (tokens s)) 'int)))
                     (cdr lines)))
          (some (fn (s)
                  (and (begins s "Cookie:")
                       (parsecookies s)))
                (cdr lines)))))

; (parseurl "GET /p1?foo=bar&ug etc") -> (get p1 (("foo" "bar") ("ug")))

(def parseurl (s)
  (let (type url) (tokens s)
    (let (base args) (tokens url #\?)
      (list (sym (downcase type))
            (sym (cut base 1))
            (if args
                (parseargs args)
                nil)))))

; I don't urldecode field names or anything in cookies; correct?

(def parseargs (s)
  (map (fn ((k v)) (list k (urldecode v)))
       (map [tokens _ #\=] (tokens s #\&))))

(def parsecookies (s)
  (map [tokens _ #\=] 
       (cdr (tokens s [or (whitec _) (is _ #\;)]))))

(def arg (req key) (alref (req 'args) key))

; *** Warning: does not currently urlencode args, so if need to do
; that replace v with (urlencode v).

(def reassemble-args (req)
  (aif (req 'args)
       (apply string "?" (intersperse '&
                                      (map (fn ((k v))
                                             (string k '= v))
                                           it)))
       ""))

(= fns* (table) fnids* nil timed-fnids* nil)

; count on huge (expt 64 10) size of fnid space to avoid clashes

(def new-fnid ()
  (check (sym (rand-string 10)) ~fns* (new-fnid)))

(def fnid (f)
  (atlet key (new-fnid)
    (= (fns* key) f)
    (push key fnids*)
    key))

(def timed-fnid (lasts f)
  (atlet key (new-fnid)
    (= (fns* key) f)
    (push (list key (seconds) lasts) timed-fnids*)
    key))

; Within f, it will be bound to the fn's own fnid.  Remember that this is
; so low-level that need to generate the newline to separate from the headers
; within the body of f.

(mac afnid (f)
  `(atlet it (new-fnid)
     (= (fns* it) ,f)
     (push it fnids*)
     it))

;(defop test-afnid req
;  (tag (a href (url-for (afnid (fn (req) (prn) (pr "my fnid is " it)))))
;    (pr "click here")))

; To be more sophisticated, instead of killing fnids, could first 
; replace them with fns that tell the server it's harvesting too 
; aggressively if they start to get called.  But the right thing to 
; do is estimate what the max no of fnids can be and set the harvest 
; limit there-- beyond that the only solution is to buy more memory.

(def harvest-fnids ((o n 20000)) 
  (when (len> fns* n) 
    (pull (fn ((id created lasts))
            (when (> (since created) lasts)    
              (wipe (fns* id))
              t))
          timed-fnids*)
    (atlet nharvest (trunc (/ n 10))
      (let (kill keep) (split (rev fnids*) nharvest)
        (= fnids* (rev keep)) 
        (each id kill 
          (wipe (fns* id)))))))

(= fnurl* "x" rfnurl* "r" rfnurl2* "y" jfnurl* "a")

(= dead-msg* "\nUnknown or expired link.")
 
(defop-raw x (str req)
  (w/stdout str 
    (aif (fns* (sym (arg req "fnid")))
         (it req)
         (pr dead-msg*))))

(defopr-raw y (str req)
  (aif (fns* (sym (arg req "fnid")))
       (w/stdout str (it req))
       "deadlink"))

; For asynchronous calls; discards the page.  Would be better to tell
; the fn not to generate it.

(defop-raw a (str req)
  (aif (fns* (sym (arg req "fnid")))
       (tostring (it req))))

(defopr r req
  (aif (fns* (sym (arg req "fnid")))
       (it req)
       "deadlink"))

(defop deadlink req
  (pr dead-msg*))

(def url-for (fnid)
  (string fnurl* "?fnid=" fnid))

(def flink (f)
  (string fnurl* "?fnid=" (fnid (fn (req) (prn) (f req)))))

(def rflink (f)
  (string rfnurl* "?fnid=" (fnid f)))
  
; Since it's just an expr, gensym a parm for (ignored) args.

(mac w/link (expr . body)
  `(tag (a href (flink (fn (,(uniq)) ,expr)))
     ,@body))

(mac w/rlink (expr . body)
  `(tag (a href (rflink (fn (,(uniq)) ,expr)))
     ,@body))

(mac onlink (text . body)
  `(w/link (do ,@body) (pr ,text)))

; bad to have both flink and linkf; rename flink something like fnid-link

(mac linkf (text parms . body)
  `(tag (a href (flink (fn ,parms ,@body))) (pr ,text)))

(mac rlinkf (text parms . body)
  `(tag (a href (rflink (fn ,parms ,@body))) (pr ,text)))

;(defop top req (linkf 'whoami? (req) (pr "I am " (get-user req))))

;(defop testf req (w/link (pr "ha ha ha") (pr "laugh")))

(mac w/link-if (test expr . body)
  `(tag-if ,test (a href (flink (fn (,(uniq)) ,expr)))
     ,@body))

(def fnid-field (id)
  (gentag input type 'hidden name 'fnid value id))

; f should be a fn of one arg, which will be http request args.
; Could also make a version that uses just an expr, and var capture.
; Is there a way to ensure user doesn't use "fnid" as a key?

(mac aform (f . body)
  (w/uniq ga
    `(tag (form method 'post action fnurl*)
       (fnid-field (fnid (fn (,ga)
                           (prn)
                           (,f ,ga))))
       ,@body)))

; Like aform except creates a fnid that will last for lasts seconds
; (unless the server is restarted).

(mac timed-aform (lasts f . body)
  (w/uniq (gl gf gi ga)
    `(withs (,gl ,lasts
             ,gf (fn (,ga) (prn) (,f ,ga)))
       (tag (form method 'post action fnurl*)
         (fnid-field (if ,gl (timed-fnid ,gl ,gf) (fnid ,gf)))
         ,@body))))

(mac arform (f . body)
  `(tag (form method 'post action rfnurl*)
     (fnid-field (fnid ,f))
     ,@body))

(mac aformh (f . body)
  `(tag (form method 'post action fnurl*)
     (fnid-field (fnid ,f))
     ,@body))

(mac arformh (f . body)
  `(tag (form method 'post action rfnurl2*)
     (fnid-field (fnid ,f))
     ,@body))

; only unique per server invocation

(= unique-ids* (table))

(def unique-id ((o len 8))
  (let id (sym (rand-string (max 5 len)))
    (if (unique-ids* id)
        (unique-id)
        (= (unique-ids* id) id))))

(def srvlog (type . args)
  (w/appendfile o (string logdir* type "-" (memodate))
    (w/stdout o (apply prs (seconds) args) (prn))))

(with (lastasked nil lastval nil)

(def memodate ()
  (let now (seconds)
    (if (or (no lastasked) (> (- now lastasked) 60))
        (= lastasked now lastval (date))
        lastval)))

)

(defop || req (pr "It's alive."))

(defop topips req
  (when (admin (get-user req))
    (whitepage
      (sptab
        (each ip (let leaders nil 
                   (maptable (fn (ip n)
                               (when (> n 100)
                                 (insort (compare > requests/ip*)
                                         ip
                                         leaders)))
                             requests/ip*)
                   leaders)
          (let n (requests/ip* ip)
            (row ip n (pr (num (* 100 (/ n requests*)) 1)))))))))

(def ttest (ip)
  (let n (requests/ip* ip) 
    (list ip n (num (* 100 (/ n requests*)) 1))))


