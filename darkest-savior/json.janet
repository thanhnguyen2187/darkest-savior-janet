(defn encode
  ```
  Encode a Janet object as JSON string. `order-key` is an optional array that
  specifies the order of the result keys if we are trying to encode a
  struct/table into an object.
  ```
  [data &opt order-key]

  (def order
    (get data order-key))

  (defn ordered-pairs
    [x]
    (if order
      (map (fn [key] [key (get x key)])
           order)
      (pairs x)))

  (cond
    (= :null data) "null"
    (number? data) (string data)
    (or (array? data)
        (tuple? data)) (as-> data _
                             (map |(encode $ order-key))
                             (string/join _ ",")
                             (string/format `[%s]` _))
    (or (string?  data)
        (buffer?  data)
        (keyword? data)) (->> data
                              string
                              (string/format `"%s"`))
    (or (struct? data)
        (table?  data)) (as-> data _
                              (ordered-pairs _)
                              (map
                                (fn [[key value]]
                                  (string/format
                                    `%s:%s`
                                    (encode key order-key)
                                    (encode value order-key)))
                                _)
                              (string/join _ ",")
                              (string/format `{%s}` _))))

(encode 1)

(-> :something
    encode
    protect)

(-> :null
    encode
    protect)

(as-> {:three 3
       :one {:four 4
             :five 5
             :six 6
             :nine 9
             :__order [:four :five :six :nine]}
       :two 2
       :__order [:one :two :three]} _
      (encode _ :__order)
      (spit "/tmp/test.json" _)
      )

((juxt array? tuple?) @[:one :two :three])


(-> {:three 3 :one 1 :two 2}
    (encode)
    protect)
