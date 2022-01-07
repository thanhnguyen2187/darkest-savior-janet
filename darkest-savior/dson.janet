(use ./zip)
(use ./skip)
(use ./bit-utils)

(import ./fake-file)
(import json)

(def- hashed-values-cache @{})

(defn hash-dson-string
  ```
  Hash a string to an int value following DSON's convention. Cache the hashed
  values.
  ```
  [str]

  (let [found-hashed-value (get hashed-values-cache str)]
    # `badd` and `bmul` is used to keep the value fits into a 32-bit int
    # and  preverse the "traditional" overflowing behavior
    (default found-hashed-value
      (-> (reduce
            (fn [new-hashed-value byte]
              (-> new-hashed-value
                  (bmul 53)
                  (badd byte)))
            0
            str)
          (|(do
              (put hashed-values-cache str $)
              $)))
      )))

(def- hashed-names
  (->> "names.txt"
       slurp
       (string/split "\n")
       ((fn [names]
          (zipcoll (map hash-dson-string names)
                   names)))))

(defn- attempt-hashed-int
  ```
  Check if the number is the hash of a meaningful string.
  ```
  [number]
  (let [found-name (get hashed-names number)]
    (if found-name
      (string "###" found-name)
      number)))


(defn decode-bytes
  ```
  Decode a DSON file's bytes and return structured data.

  The bytes can generally split into three parts:

  - `header`
  - `meta-1-blocks`
  - `meta-2-blocks`
  - `fields`

  The purposes and decoding of each part can be read from the corresponding
  functions.
  ```
  [bytes]

  (def fake-dson-file
    ```
    At first, `decode-dson-bytes` is named `read-dson-file` which takes a file
    path and expected to return the structured data. There can be other fully
    shaped DSON bytes structures embedded within the file, however. The approach
    then leads us to creating a temporary file, which seems clunky.

    A simple solution of `fake-file` to keep track of the current reading
    cursor's index then is implemented.
    ```
    (fake-file/make bytes))

  (defn read-raw
    ```
    Read `n` raw bytes from the file.
    ```
    [n]
    (fake-file/read fake-dson-file
                    n))

  (defn read-int
    ```
    Read 4 bytes into an integer.
    ```
    []
    (buffer->int (read-raw 4)))

  (defn decode-header
    ```
    Decode the first 64 bytes of the file which contain general metadata.

    - `magic-number`: must be "\x01\xB1\0\0"
    - `revision`
    - `header-length`: always is `64`
    - `zeroes`: zero-filled bytes
    - `meta-1-size`: size of `meta-1-blocks`
    - `num-meta-1-entries`: meta 1 blocks count
    - `meta-1-offest`
    - `zeroes-2`: zero-filled bytes
    - `zeroes-3`: zero-filled bytes
    - `num-meta-2-entries`: meta 2 blocks count
    - `meta-2-offest`
    - `zeroes-4`: zero-filled bytes
    - `data-length`: length of the fields
    - `data-offset`
    ```
    []
    # `(table ...)` is used instead of `@{}` since
    # `(table ...)` preserve the calling order of `(read-raw)`,
    # while `@{}` does not
    (table
     :magic-number       (read-raw 4)
     :revision           (read-raw 4)
     :header-length      (read-int)
     :zeroes             (read-raw 4)
     :meta-1-size        (read-int)
     :num-meta-1-entries (read-int)
     :meta-1-offset      (read-int)
     :zeroes-2           (read-raw 8)
     :zeroes-3           (read-raw 8)
     :num-meta-2-entries (read-int)
     :meta-2-offset      (read-int)
     :zeroes-4           (read-raw 4)
     :data-length        (read-int)
     :data-offset        (read-int)))

  (def header (decode-header))

  (defn decode-meta-1-block
    ```
    Decode a "meta 1" block which contains the data to build up DSON's tree
    structure.
    ```
    []
    (table :parent-index        (read-int)
           :meta-2-entry-idx    (read-int)
           :num-direct-children (read-int)
           :num-all-children    (read-int)))

  (defn decode-meta-1-blocks
    ```
    Decode `n` meta 1 blocks.
    ```
    [n]
    (seq [index :range [0 n]]
      (merge-into (decode-meta-1-block)
                  {:index index})))

  (defn infer-meta-2-block
    ```
    Infer new data from the decoded "meta 2" block.

    The block is 4-byte aligned, which means:

    - `8` is not touched
    - `11` gets padded `1` byte to become `12`
    - `21` gets padded `3` bytes to become `24`
    ```
    [meta-2-block]
    (def data
      (let [field-info (get meta-2-block :field-info)]
        (table :is-primitive      (-> field-info
                                      (band 2r1))
               :field-name-length (-> field-info
                                      (band 2r11111111100)
                                      (brshift 2))
               :meta-1-entry-idx  (-> field-info
                                      (band 2r1111111111111111111100000000000)
                                      (brshift 11)))))
    (let [raw-data-offset (+ (meta-2-block :offset)
                             (data         :field-name-length))
          aligned-bytes-count (-> raw-data-offset
                                  (/ 4)
                                  math/ceil
                                  (* 4)
                                  (- raw-data-offset))]
      (merge-into data
                  {:raw-data-offset     raw-data-offset
                   :aligned-bytes-count aligned-bytes-count})))

  (defn decode-meta-2-block
    ```
    Decode a "meta 2" block which contains data about the fields of the DSON
    file.

    - `name-hash` is the field's name ran through `hash-dson-string`
    - `offset` is the field's starting index
    - `field-info` is the field's bits to infer other data
    ```
    []
    (def data
      (table :name-hash (read-int)
             :offset (read-int)
             :field-info (read-int)))
    (merge-into data
                {:inferences (infer-meta-2-block data)}))

  (defn decode-meta-2-blocks
    ```
    Decode `n` meta 2 blocks from file.

    `raw-data-length` is inferred by the difference between the second (next)
    block's offset, and sum of the first (previous)'s offset and field name
    length. The last block's `raw-data-length` can be calculated, using
    `data-length` from header as the second offset.
    ```
    [n]

    (def meta-2-blocks
      (seq
        [index :in (range n)]
        (merge-into (decode-meta-2-block)
                    {:index index})))

    (map (fn [[block-1 block-2]]
           (put-in block-1
                   [:inferences :raw-data-length]
                   (- (get block-2 :offset)
                      (+ (get block-1 :offset)
                         (get-in block-1 [:inferences
                                          :field-name-length])))))
         (zip meta-2-blocks
              [;(slice meta-2-blocks 1)
               {:field-info 0
                :index math/inf
                :inferences {}
                :name-hash 0
                :offset (header :data-length)}]))

    meta-2-blocks)

  (defn infer-field
    ```
    Infer if a field is an object and. In case it is, find out how many children
    does it have. The data is needed for later hierarchy structure building.
    ```
    [meta-1-blocks
     field]
    (let [index               (field :index)
          meta-1-entry-idx    (field :meta-1-entry-idx)
          meta-1-block        (meta-1-blocks meta-1-entry-idx)
          num-direct-children (meta-1-block :num-direct-children)
          meta-2-entry-idx    (meta-1-block :meta-2-entry-idx)
          is-object           (= index meta-2-entry-idx)]
      (put field :inferences (table :is-object is-object
                                    :num-direct-children (if is-object
                                                           num-direct-children
                                                           :null)))))

  (defn infer-fields-hierarchy
    ```
    Infer fields hierarchy by a stack, since the fields are laid out
    sequentially with a "num-direct-children" within each.

    Example:

      [{:id 1 :num-direct-children 3}
       {:id 2 :num-direct-children :null}
       {:id 3 :num-direct-children 2}
       {:id 4 :num-direct-children :null}
       {:id 5 :num-direct-children :null}
       {:id 6 :num-direct-children :null}]

    It means the hierarchy looks like this:

      1 --> 2
       \--> 3 --> 4
       |     \--> 5
       \--> 6
    ```
    [meta-1-blocks
     fields]

    (let [objects-stack @[@{:field-index         -1
                            :field-name          :null
                            :num-remain-children 1}]]

      (defn decrease-last-num-remain-children
        []
        (-> objects-stack
            last
            (update :num-remain-children dec)))

      (defn infer-parent-field-index
        [field]
        (put-in field
                [:inferences :parent-field-index]
                (-> objects-stack
                    last
                    (get :field-index))))

      (defn remove-fulfilled-object
        []
        (if (= 0 (-> objects-stack
                     last
                     (get :num-remain-children)))
          (array/pop objects-stack)))

      (defn add-new-object
        [field]
        (if (and (get-in field [:inferences :is-object])
                 (pos? (get-in field [:inferences :num-direct-children])))
          (let [field-index         (get field :index)
                field-name          (get field :name)
                num-remain-children (get-in field [:inferences :num-direct-children])
                new-object          @{:field-index field-index
                                      :field-name field-name
                                      :num-remain-children num-remain-children}]
            (array/push objects-stack new-object))))

      (loop [field :in fields]
        (infer-parent-field-index field)
        (decrease-last-num-remain-children)
        (remove-fulfilled-object)
        (add-new-object field)))

    (defn infer-hierarchy-path
      ```
      Do a simple DFS that depends on `parent-field-index` to infer the
      hierarchy path of the field. DFS should stop at field 0, which is
      `base_root`.
      ```
      [field &opt current-names]
      (default current-names @[])
      (if (= (field :index) 0)
        current-names
        (let [field-name (get field :name)
              parent-field-index (get-in field [:inferences :parent-field-index])
              parent-field (get fields parent-field-index)]
          (infer-hierarchy-path parent-field
                                 (array/push current-names field-name)))))

    (->> fields
         (map |(put-in $
                       [:inferences :hierarchy-path]
                       (reverse (infer-hierarchy-path $))))))

  (defn infer-field-data-type
    ```
    Infer field's data type for later raw data decoding.
    ```
    [field]

    (defn process-by-hard-coded-values
      ```
      Infer field's data type by hard-coded field names and hard-coded hierarchy
      paths.
      ```
      [field]
      (let [field-name     (field :name)
            hierarchy-path (get-in field [:inferences :hierarchy-path])]
        (cond

          (or
            (case field-name
              "requirement_code" true
              false))
          :char

          (or
            (case field-name
              "current_hp" true
              "m_Stress"   true
              false)
            (match hierarchy-path
              ["actor" "buff_group" _ "amount"] true
              ["chapter" _ _ "percent"]         true
              _                                 false))
          :float

          (or
            (case field-name
              "read_page_indexes"                                      true
              "raid_page_indexes"                                      true
              "raid_unpage_indexes"                                    true
              "dungeons_unlocked"                                      true
              "played_video_list"                                      true
              "trinked_retention_ids"                                  true
              "last_party_guids"                                       true
              "dungeon_history"                                        true
              "buff_group_guids"                                       true
              "result_event_history"                                   true
              "dead_hero_entries"                                      true
              "additional_mash_disabled_infestation_monster_class_ids" true
              "skill_cooldown_keys"                                    true
              "skill_cooldown_values"                                  true
              "bufferedSpawningSlotsAvailable"                         true
              "raid_finish_quirk_monster_class_ids"                    true
              "narration_audio_event_queue_tags"                       true
              "dispatched_events"                                      true
              false)
            (match hierarchy-path
              ["mash" "valid_additional_mash_entry_indexes"] true
              ["party" "heroes"]                             true
              ["curioGroups" _ "curios"]                     true
              ["curioGroups" _ "curio_table_entries"]        true
              ["backer_heroes" _ "combat_skills"]            true
              ["backer_heroes" _ "camping_skills"]           true
              ["backer_heroes" _ "quirks"]                   true
              _                                              false))
          :int-vector

          (or
            (case field-name
              "goal_ids"        true
              "quirk_group"     true
              "backgroundNames" true
              false)
            (match hierarchy-path
              ["roaming_dungeon_2_ids" _ "s"]                   true
              ["backgroundGroups" _ "backgrounds"]              true
              ["backgroundGroups" _ "background_table_entries"] true
              _                                                 false))
          :string-vector

          (or
            (match hierarchy-path
              ["map" "bounds"]                true
              ["areas" _ "bounds"]            true
              ["areas" _ "tiles" _ "mappos"]  true
              ["areas" _ "tiles" _ "sidepos"] true
              _                               false))
          :float-vector

          (or
            (case field-name
              "killRange" true
              false))
          :two-int

          :unknown)))

    (defn process-by-heuristic
      ```
      Infer field's data type by data length or other clues. `:file` is
      `:string` with magic number.
      ```
      [field]

      (let [raw-data        (field :raw-data-stripped)
            raw-data-length (if (= :null raw-data)
                              0
                              (length raw-data))]
        (cond

          (= raw-data-length 1)
          (let [byte (get-in field [:raw-data 0])]
            (if (and (>= 0x20 byte)
                     (<= 0x7E byte))
              :char
              :bool))

          (and (= raw-data-length 8)
               (all |(or (zero? $)
                         (one?  $))
                    (map |(buffer->int $)
                         (partition 4 raw-data))))
          :two-bool

          (= raw-data-length 4)
          :int

          (and (>= raw-data-length 8)
               (= (slice raw-data 4 8) "\x01\xB1\0\0"))
          :file

          (>= raw-data-length 5)
          :string

          :unknown
          )))

    (-> field
        (get-in [:inferences :is-object])
        (|(case $
            true  :object
            :unknown))
        (|(case $
            :unknown (process-by-hard-coded-values field)
            $))
        (|(case $
            :unknown (process-by-heuristic field)
            $))
        ))

  (defn infer-field-data
    ```
    Infere field data by data type.

    - `:char`: simply return the data
    - `:float`: turn four bytes of raw data into a float by IEEE 754
    - `:int-vector`: skip the first four bytes that indicates array length and
      turn the rest into an int array
    - `:float-vector`: skip the first four bytes that indicates array length and
      turn the rest into a float array
    - `:two-int`: parse the first four bytes and the next four bytes
    - `:bool`: check if the last bit is toggled
    - `:two-bool`: check if the last bit of the two bytes are toggled
    ```
    [field]

    (defn decode-string-vector
      [bytes]
      ```
      The bytes have this order:

        | n | m1 | data | \0 | m2 | data | \0 | ...

      Which means after having the vector length `n`, we have strings that are
      `m1`-character long, `m2`-character long, etc.

      For the actual work, we read `n`, and then repeat a process of reading
      `m`s and data `n` times.
      ```
      (let [ff (fake-file/make bytes)
            n (-> ff
                  (fake-file/read 4)
                  buffer->int)]
        (seq [_ :in (range n)]
          (-> ff
              (fake-file/read 4)
              (buffer->int)
              (|(fake-file/read ff $))
              (slice 0 -2) # the resulting string have a redundant `\0`
              ))))

    (let [data-type (get-in field [:inferences :data-type])
          raw-data  (field :raw-data-stripped)]
      (case data-type
        :char          raw-data
        :float         (buffer->float raw-data)
        # TODO: find out what does 1972053455 of "persist.tutorial.json" means
        #       since within the file, the value stood out from the values of
        #       hashed int vector
        :int-vector    (->> raw-data
                            (|(skip $ 4))
                            (partition 4)
                            (map buffer->int)
                            (map attempt-hashed-int))
        :string-vector (decode-string-vector raw-data)
        :float-vector  (->> raw-data
                            (|(skip $ 4))
                            (partition 4)
                            (map buffer->float))
        # :two-int       [(buffer->int raw-data)
        #                 (buffer->int (skip raw-data 4))]
        :two-int       (->> raw-data
                            (partition 4)
                            (map buffer->int))
        :bool          (= 1 (raw-data 0))
        :two-bool      [(= 1 (raw-data 0))
                        (= 1 (raw-data 1))]
        :int           (->> raw-data
                            buffer->int
                            attempt-hashed-int)
        :file          (-> raw-data
                           (skip 4)
                           decode-bytes)
        :string        (slice raw-data 4 -2)
        :unknown
        )))

  (defn decode-field
    ```
    Decode a field which is the actual data of a DSON file using a meta 2 block.
    ```
    [meta-2-block]
    (let [inferences          (meta-2-block :inferences)
          index               (meta-2-block :index)
          meta-1-entry-idx    (inferences :meta-1-entry-idx)
          field-name-length   (inferences :field-name-length)

          field-name          (slice (read-raw field-name-length) 0 -2) # the string include "\0" at its tail
          raw-data-length     (inferences :raw-data-length)
          raw-data            (read-raw raw-data-length)
          aligned-bytes-count (inferences :aligned-bytes-count)
          raw-data-stripped   (if (> raw-data-length aligned-bytes-count)
                                (slice raw-data aligned-bytes-count)
                                raw-data)]
      (table :index index
             :meta-1-entry-idx meta-1-entry-idx
             :name field-name
             :name-hash (hash-dson-string field-name)
             :raw-data-length raw-data-length
             :raw-data raw-data
             :raw-data-stripped raw-data-stripped)))

  (defn decode-fields
    ```
    Decode fields. Meta 2 blocks are needed for the actual data decoding. Meta 1
    blocks are needed for the structure building.
    ```
    [meta-1-blocks
     meta-2-blocks]
    (->> meta-2-blocks
         (map decode-field)
         (map |(infer-field meta-1-blocks $))
         (infer-fields-hierarchy meta-1-blocks)
         (map |(put-in $
                       [:inferences :data-type]
                       (infer-field-data-type $)))
         (map |(put-in $
                       [:inferences :data]
                       (infer-field-data $)))))

  # finally, we can return the data itself
  (let [meta-1-blocks (-> header
                          (get :num-meta-1-entries)
                          decode-meta-1-blocks)
        meta-2-blocks (-> header
                          (get :num-meta-2-entries)
                          decode-meta-2-blocks)
        fields        (decode-fields meta-1-blocks
                                     meta-2-blocks)]
    (table :header        header
           :meta-1-blocks meta-1-blocks
           :meta-2-blocks meta-2-blocks
           :fields        fields
           )))


(defn read-file-bytes
  ```
  Read bytes of a file.
  ```
  [path]
  (-> path
      (file/open :rb)
      (file/read :all)))


(defn data->table
  ```
  Turn structured DSON data into a table for later JSON encoding.
  ```
  [dson-data]

  (def fields (dson-data :fields))
  (def partial-transformed-fields
    (seq [field :in fields]
      (let [field-name         (get    field :name)
            data-type          (get-in field [:inferences :data-type])
            data               (get-in field [:inferences :data])
            is-object          (get-in field [:inferences :is-object])
            is-file            (= data-type :file)
            parent-field-index (get-in field [:inferences :parent-field-index])]
        @{field-name            (cond
                                  is-object @{}
                                  is-file (-> data
                                              (get :fields)
                                              fields->table)
                                  data)
          :__parent-field-index parent-field-index})))

  (map (fn [partial-transformed-field]
         (-?> partial-transformed-field
              (|(do
                  (def parent-field-index (get $ :__parent-field-index))
                  (put $ :__parent-field-index nil)
                  parent-field-index))
              (|(get partial-transformed-fields $))
              (|(merge-into (-?> $
                                 keys
                                 first
                                 $)
                            partial-transformed-field))))
       partial-transformed-fields)

  (map |(put $ :__parent-field-index nil)
       partial-transformed-fields)

  (put (partial-transformed-fields 0)
       :__revision (get-in dson-data [:header :revision])))


(defn table->data
  ```
  Turn a table into DSON data. The table should come from `data->table` or at
  least have a `:__revision` ready.
  ```
  [tbl-with-revision]

  (def tbl
    (->> tbl-with-revision
         pairs
         (filter
           (fn [[key value]] (not= key :__revision)))))

  (def revision
    (tbl-with-revision :__revision))

  (def header
    (table
      :magic-number "\x01\xB1\0\0"
      :revision revision
      :zeroes "\0\0\0\0"
      :meta-1-size 0
      :num-meta-1-entries (->> tbl
                               (count (fn [[_ value]]
                                         (or (table? value)
                                             (struct? value)))))
      :meta-1-offset 0
      :zeroes-2 "\0\0\0\0\0\0\0\0"
      :zeroes-3 "\0\0\0\0\0\0\0\0"
      :num-meta-2-entries (-> tbl
                              pairs
                              length)
      :meta-2-offset 0
      :zeroes-4 "\0\0\0\0"
      :data-length 0
      :data-offset 0
      ))

  {:header header})


(defn read-dson-file
  [path]
  (-> path
      dson/read-file-bytes
      dson/decode-bytes))

