(defn skip
  ```
  Skip the first `n` elements of a collection.
  ```
  [coll n]
  (case (type coll)
    :array  (array/slice  coll n)
    :tuple  (tuple/slice  coll n)
    :string (string/slice coll n)
    :buffer (buffer/slice coll n)
    (error
      (string (describe coll)
              ": not an indexed type!"))))

