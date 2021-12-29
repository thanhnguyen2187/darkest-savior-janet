(defn skip
  ```
  Skip the first `n` elements of a collection.
  ```
  [coll n]
  (case (type coll)
    :array (array/slice coll n)
    :tuple (tuple/slice coll n)
    (error "Not an indexed type!")
    )
  )

