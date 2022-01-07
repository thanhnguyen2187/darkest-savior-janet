(defn print-lines
  [lines]
  (map print lines))


(defn dispatch
  [state]
  (case state
    :help
    (do
      (print
        ```
        darkest-savior

        Darkest Dungeon save editor

        Ruin has come to our command line.

                                        - The Ancestor (probably) -

        Usage:

          --help/-h           show help
          --interactive/-i    interactive mode
          --convert/-c        converting mode
          --from/-f [path]    path to a source Darkest Dungeon JSON file
          --to/-t [path]      the destination JSON file; default to
                              the source file's name

        Example:

          darkest-savior -i
          darkest-savior -c -f /some/persist.dson-file.json -t /another/file.json
        ```)
        )
    (do
      (print "Invalid input!")
      (os/exit))))


(defn main
  [& args]

  (defn find-flag
    [short-flag
     long-flag]
    (find args
          (fn [arg]
            (or (= short-flag arg)
                (= long-flag arg)))
          false))

  (defn find-value
    [arg & dflt-value]

    (let [index (find-index args |(= $ arg))
          value (-> index
                    inc
                    (|(get args $)))]
      (default value dflt-value)))

  (cond
    (find-flag "-h" "--help")
    (dispatch :help)

    (find-flag "-i" "--interactive")
    (dispatch :interactive)

    (find-flag "-c" "--convert")
    (dispatch :convert)



    (dispatch :invalid)))
