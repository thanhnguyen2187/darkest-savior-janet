
(var input "")

(while (not (= input "exit"))
  (print "================================================================================")
  (print "Welcome to Darkest Saviour, which is a simple save editor for Darkest Dungeon.")
  (print "Please input \"exit\" to stop the program.")
  (prin "Please input your save location: ")
  (set input (string/trim (file/read stdin
                                     :line))))

(defn compare-buffers
  "Compare first `n` bytes of two buffers."
  [buffer-1 buffer-2 n]
  (defn iterate
    [buffer-1 buffer-2 index]
    (if (>= index n)
      true
      (and (= (get buffer-1 index)
              (get buffer-2 index))
           (iterate buffer-1
                    buffer-2
                    (+ index 1)))))
  (iterate buffer-1 buffer-2 0))
