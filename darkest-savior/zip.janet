(defn zip
  "Create a new array that consists of the elements of two collections."
  [coll-1 coll-2]
  (map tuple
       coll-1
       coll-2))

