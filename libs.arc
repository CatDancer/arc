(load "strings.arc")

(def len- (a b)
  (- len.a len.b))

(def snip-left (pat str)
  (if (begins str pat)
       (cut str len.pat)))

(def ends (pat str)
  (and (<= len.pat len.str)
       (is (cut str (len- str pat)) pat)))

(def snip-right (pat str)
  (if (ends pat str)
       (cut str 0 (len- str pat))))

(def list-afters ()
  (map [map sym (tokens _ #\:)]
       (trues [snip-left "after:" _] (dir "lib"))))

(def list-libs ()
  (sort < (map sym (trues [snip-right ".arc" _] (dir "lib")))))

(def cant-load-yet (to-load afters lib)
  (some (fn ((before after))
          (and (is after lib)
               (mem before to-load)))
        afters))

(def next-to-load (to-load afters)
  (find [~cant-load-yet to-load afters _] to-load))

(def load-libs ()
  (with (to-load (list-libs)
         afters  (list-afters))
    (while to-load
      (aif (next-to-load to-load afters)
            (do (load (string "lib/" it ".arc"))
                (zap [rem it _] to-load))
            (err "after loop in loading libs" to-load)))))

(ensure-dir "lib")
(load-libs)
