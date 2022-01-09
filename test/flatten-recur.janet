(use "../darkest-savior/flatten-recur")


(-> {:key-1 1
    :key-2 {:key-4 {:key-5 5}
            :key-6 {:key-7 7}}
    :key-3 3}
    flatten-recur
    freeze
    (= {[:key-1] 1
        [:key-2 :key-4 :key-5] 5
        [:key-2 :key-6 :key-7] 7
        [:key-3] 3}))

