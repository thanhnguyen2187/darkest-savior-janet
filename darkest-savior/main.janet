(defn dispatch-output
  [state]
  (case state
    :help
    (fn []
      (print
        ```
        darkest-savior

        Darkest Dungeon save editor

        Ruin has come to our command line.

                                        - The Ancestor (probably) -

        Usage:

          --help/-h           show help
          --interactive/-i    interactive mode
          --convert/-c        converting flag
          --from/-f [path]    path to a source Darkest Dungeon JSON file
          --to/-t [path]      the destination JSON file; defaults to
                              the source file's name

        Example:

          # start interactive mode
          darkest-savior -i
          # convert DSON to JSON
          darkest-savior -c -f /some/persist.dson-file.json -t /another/file.json
          # convert JSON to DSON
          darkest-savior -c -f /some/file.json -t /another/persist.dson-file.json
        ```)
        )
    (fn []
      (print "Invalid input!")
      (os/exit))))


(defn dispatch-action
  [state]
  (case state
    :interactive-start
    (fn []
      (print ```
             Started Darkest Savior's interactive mode
             ```))
    ))


(defn main
  [& args]

  (defn find-flag
    [short-flag
     long-flag]
    (find (fn [arg]
            (or (= short-flag arg)
                (= long-flag arg)))
          args
          false))

  (defn find-value
    [arg-short
     arg-long
     &opt dflt-value]

    (let [index (find-index args |(or (= arg-short $)
                                      (= arg-long  $)))
          value (-?> index
                     inc
                     (|(get args $)))]
      (default value dflt-value)))

  (defn get-file-name
    [path]

    (def system-separator
      (case (os/which)
        :windows `\`
        :linux `/`))

    (->> path
         (string/split system-separator)
         last))

  (cond
    (or
      # `darkest-savior` is called without any other argument
      (-> args
          length
          (= 1))
      (find-flag "-h" "--help"))
    (-> :help
        dispatch-output
        apply)

    (find-flag "-i" "--interactive")
    (dispatch-action :interactive)

    (find-flag "-c" "--convert")
    (let [from-arg-value (find-value "-f" "--from")
          to-arg-value   (find-value "-t" "--to")]
      )

    (dispatch-output :invalid)))

