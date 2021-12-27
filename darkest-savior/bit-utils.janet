(defn buffer->int-old
  ```
  Turn the first `n` bytes of a buffer into an integer.
  ```
  [buffer_ n &opt encoding]
  (default encoding :little-endian)
  (defn iterate
    [current-sum
     buffer_
     index]
    (if (< index n)
      (iterate (bor current-sum
                    (blshift (get buffer_ index)
                             (* 8 index)))
               buffer_
               (inc index))
      current-sum))
  (match encoding
    :little-endian (iterate 0
                            buffer_
                            0)
    :big-endian (iterate 0
                         (reverse (buffer/slice buffer_ 0 n))
                         0)))


(defn buffer->int
  ```
  Turn a 4-byte buffer into a 32-bit integer following little endian encoding.
  ```
  [buf]
  (bor (blshift (buf 0) 0)
       (blshift (buf 1) 8)
       (blshift (buf 2) 16)
       (blshift (buf 3) 24)))


(defn buffer->float
  ```
  Turn a 4-byte buffer into a float following IEEE 754.
  ```
  [buf]

  (defn bmantissa
    [number]
    (defn iterate
      [number counter result]
      (if (= counter 0)
        result
        (iterate (brshift number 1)
                 (dec counter)
                 (if (odd? number)
                   (+ result (math/pow 2 (- counter)))
                   result))))
    (iterate number 23 0))

  (let [bits     (buffer->int buf)
        sign     (-> bits
                     (band 2r1_00000000_00000000000000000000000)
                     (brshift 31))
        exponent (-> bits
                     (band 2r0_11111111_00000000000000000000000)
                     (brshift 23)
                     (- 127))
        mantissa (-> bits
                     (band 2r0_00000000_11111111111111111111111)
                     bmantissa
                     )]
    (* sign
       (math/pow 2 exponent)
       (+ 1 mantissa))))


(defn badd
  ```
  Add two 32-bit integers.
  ```
  [a b]
  (cond
    (= a 0) b
    (= b 0) a
    (badd (blshift (band a b)
                   1)
          (bxor a b))))


(defn bmul
  ```
  Multiply two 32-bit integers.
  ```
  [a b]
  (cond
    (or (= a 0)
        (= b 0)) 0
    (= a 1) b
    (= b 1) a
    (badd (bmul a (band b 1))
          (blshift (bmul a (brshift b 1)) 1)
          )))

