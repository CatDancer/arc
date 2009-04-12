(def mzlib (spec name)
  (mz (parameterize ((current-namespace (make-namespace)))
        (namespace-require (ac-denil spec))
        (eval name))))

(= mz-system (mzlib '(lib "process.ss") 'system))

(= lib-url-schemes* '("http://" "https://"))

(def alib-url (x)
  (and (is (type x) 'string)
       (some [begins x _] lib-url-schemes*)))

(def anarcfile (url)
  (endmatch ".arc" url))

(def lib-url-path (url)
  (or (some (fn (scheme) (and (begins url scheme) (cut url (len scheme)))) lib-url-schemes*) (err (string "not a url: " url))))

(def lib-path (url)
  (string "lib/" (lib-url-path url)))

(def lib-cache-path (url)
  (string "lib/cache/" (lib-url-path url)))

(def lib-pull urls
  (ensure-dir "lib/cache")
  (or (mz-system (string "cd lib/cache; wget -nv -x -N "
                         (apply string (intersperse " " urls))
                         " 2>/dev/null"))
      (err (string "unable to pull " url)))
  'ok)

(def lib-list-dir (d baseurl)
  (mappend (fn (entry)
             (let path (string d "/" entry)
               (if ((mz file-exists?) path)
                    (list (string baseurl "/" entry))
                   ((mz directory-exists?) path)
                    (lib-list-dir (string d "/" entry) (string baseurl "/" entry)))))
           (dir d)))

(def lib-list ()
  (mappend (fn (entry)
             (let path (string "lib/" entry)
               (if ((mz file-exists?) path)
                    (list (string "http://" entry))
                   ((mz directory-exists?) path)
                    (lib-list-dir path (string "http://" entry)))))
           (rem "cache" (dir "lib"))))

(def lib-pull-all ()
  (apply lib-pull (lib-list))
  'ok)

(def lib-new ()
  (lib-pull-all)
  (map (fn (url)
         (if (mz-system:string "cmp -s " (lib-path url) " " (lib-cache-path url))
             (prn url)))
       (lib-list))
  'ok)

; "foo/bar/file" -> "foo/bar/"
(def path-dirpart (path)
  (mz (path->string (let-values (((dir a b) (split-path path))) dir))))

(= lib-loaded* (table))

(def lib-fetch (url)
  (lib-pull url)
  (ensure-dir (path-dirpart (lib-path url)))
  (or (mz-system (string "cp -p " (lib-cache-path url) " " (lib-path url)))
      (err (string "unable to copy cached copy of " url " into the lib directory")))
  (wipe lib-loaded*.url)
  'ok)

(def lib (url)
  (unless (alib-url url) (err (string "not a url: " url)))
  (unless (lib-loaded* url)
    (unless ((mz file-exists?) (lib-path url))
      (lib-fetch url))
    (if (anarcfile url) (load (lib-path url)))
    (assert lib-loaded*.url))
  'ok)
