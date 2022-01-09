(defn- structured?
  [x]
  (or (table?  x)
      (struct? x)))


(defn flatten-recur
  ```
  Flatten a table or struct. Resulting in a table that have the nested keys
  turned into tuples.
  ```
  [x]

  (defn recurse
    [element prev-keys result]
    (if (structured? element)
      (do
        (->> element
             pairs
             (map (fn [[key value]]
                    (let [new-key [;prev-keys key]]
                      [new-key value])))
             (map (fn [[key value]]
                    (if (structured? value)
                      (recurse value key result)
                      (put result key value)))))
        result)
      result))

  (recurse x [] @{}))

