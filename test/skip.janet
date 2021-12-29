(import ../darkest-savior/skip :prefix "")

(assert (= (skip [1 2 3] 1)
           [2 3]))
(assert (= (-> @[1 2 3]
               (skip 1)
               (array/push 4)
               freeze)
           [2 3 4]))

(skip @[1 2 3 4 5 6] 2)
