(defn make
  ```
  Create a fake file from bytes which persist current cursor's index. Fake files
  also save us the headaches of creating a temporary file and cleaning up
  afterwards. Two specific use cases with DSON can be listed here:

  - A DSON file is embedded within another: we simply pass the raw bytes as a
  to the main reading function again
  - A string vector field is encountered: a fake file that persist the current
  reading state fits perfectly
  ```
  [bytes]
  (var cursor 0)
  (fn [n]
    (do
      (def result (string/slice bytes cursor (+ cursor n)))
      (+= cursor n)
      result)))


(defn read
  [fake-file n]
  (fake-file n))

