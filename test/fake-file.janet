(import ../darkest-savior/fake-file)


(assert (-> @"\x00\x01\x02\x99"
            fake-file/make
            (fake-file/read 2)
            (= "\x00\x01")))
(assert (-> @"\x00\x01\x02\x99"
            fake-file/make
            (|(do
                (assert (= (fake-file/read $ 1)
                           "\x00"))
                $))
            (|(do
                (assert (= (fake-file/read $ 1)
                           "\x01"))
                $))
            (|(assert (= "\x02\x99"
                         (fake-file/read $ 2))))))
