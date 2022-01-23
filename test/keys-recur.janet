(use ../darkest-savior/keys-recur)


(-> {:one 1 :two 2}
    keys-recur
    freeze
    (= [:one :two])
    assert)

(-> {:one 1
     :two {:three 3
           :four 4}}
    keys-recur
    sort
    freeze
    (= [:four :one :three :two])
    assert)

(-> {:one 1
     :two {:three 3
           :four 4}
     :five {:six {:seven 7}}}
    keys-recur
    sort
    freeze
    (= [:five :four :one :seven :six :three :two])
    assert)

