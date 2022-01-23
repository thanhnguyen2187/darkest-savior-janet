(defn keys-recur
  ```
  Like `keys`, but recursively.
  ```
  [tbl]

  (defn recurse
    [element]
    (if (or (table?  element)
            (struct? element))
      (array/concat (-> element
                        keys)
                    (->> element
                         values
                         (map recurse)
                         flatten))
      []))

  (->> tbl
       recurse))

