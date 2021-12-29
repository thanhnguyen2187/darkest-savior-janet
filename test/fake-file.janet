(use ../darkest-savior/fake-file)


(assert (-> @"\x00\x01\x02\x99"
            make-fake-file
            (read-fake-file 2)
            (= "\x00\x01")))
(assert (-> @"\x00\x01\x02\x99"
            make-fake-file
            (|(do
                (assert (= (read-fake-file $ 1)
                           "\x00"))
                $))
            (|(do
                (assert (= (read-fake-file $ 1)
                           "\x01"))
                $))
            (|(assert (= "\x02\x99"
                         (read-fake-file $ 2))))))
