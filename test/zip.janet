(import ../darkest-savior/zip :prefix "")

(assert (= [[1 2] [3 4] [5 6]]
           (freeze (zip [1 3 5] [2 4 6]))))
(assert (not= [[-1 2] [3 4]]
              (freeze (zip [1 3 5] [2 4 6]))))

