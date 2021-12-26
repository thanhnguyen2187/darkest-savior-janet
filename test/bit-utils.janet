(import ../darkest-savior/bit-utils :prefix "")

(assert (= (buffer->int "\x00\x00\x00\x00")
           0))
(assert (= (buffer->int "\x00\x00\x00\x02")
           33554432))
(assert (= (buffer->int (buffer/push-word @"" 2187))
           2187))
