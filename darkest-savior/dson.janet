(import ./zip :prefix "")
(import ./bit-utils :prefix "")


(defn hash-dson-string
  [str]
  (var value 0)
  (loop [byte :in str]
    (set value
         (badd (bmul value 53)
               byte)))
  value)


(defn make-fake-file
  "Create a fake file from bytes."
  [bytes]
  (var cursor 0)
  (fn [n]
    (do
      (def result (string/slice bytes cursor (+ cursor n)))
      (+= cursor n)
      result)))

(defn read-fake-file
  [fake-file n]
  (fake-file n))

# TODO: replace "read" with a better word
(defn read-dson-bytes
  ```
  Read bytes of a Darkest Dungeon json file.
  ```
  [bytes]

  (def fake-dson-file
    (make-fake-file bytes))

  (defn read-raw
    "Read `n` raw bytes from the file."
    [n]
    (read-fake-file fake-dson-file n))

  (defn read-int
    "Read 4 bytes into an integer."
    []
    (buffer->int (read-raw 4)))

  (def header
    (table
     :magic-number (read-raw 4)
     :revision (read-raw 4)
     :header-length (read-int)

     :zeroes (read-raw 4)

     :meta-1-size (read-int)
     :num-meta-1-entries (read-int)
     :meta-1-offset (read-int)

     :zeroes-2 (read-raw 8)
     :zeroes-3 (read-raw 8)

     :num-meta-2-entries (read-int)
     :meta-2-offset (read-int)

     :zeroes-4 (read-raw 4)

     :data-length (read-int)
     :data-offset (read-int)))

  (defn read-meta-1-block
    []
    (table :parent-index (read-int)
           :meta-2-entry-idx (read-int)
           :num-direct-children (read-int)
           :num-all-children (read-int)))

  (defn read-meta-1-blocks
    "Read `n` meta 1 blocks from file."
    [n]
    (let [index 0
          meta-1-blocks @[]]
      (loop [index :range [0 n]]
        (array/push meta-1-blocks
                    (merge-into (read-meta-1-block)
                                {:index index})))
      meta-1-blocks))

  (defn infere-meta-2-block
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
          aligned-bytes (-> raw-data-offset
                            (/ 4)
                            math/ceil
                            (* 4)
                            (- raw-data-offset))]
      (merge-into data
                  {:raw-data-offset raw-data-offset
                   :aligned-bytes   aligned-bytes})))

  (defn read-meta-2-block
    []
    (def data
      (table :name-hash (read-int)
             :offset (read-int)
             :field-info (read-int)))
    (merge-into data
                {:inferences (infere-meta-2-block data)}))

  (defn read-meta-2-blocks
    ```
    Read `n` meta 2 blocks from file. `raw-data-length` is inferred by the
    difference between the second (next) block's offset, and sum of the first
    (previous)'s offset and field name length. The last block's
    `raw-data-length` can be calculated, using `data-length` from header as
    the second offset.
    ```
    [n]

    (def meta-2-blocks
      (seq
        [index :in (range n)]
        (merge-into (read-meta-2-block)
                    {:index index})))
    (map (fn [[block-1 block-2]]
           (put-in block-1
                   [:inferences :raw-data-length]
                   (- (get block-2 :offset)
                      (+ (get block-1 :offset)
                         (get-in block-1 [:inferences
                                          :field-name-length])))))
         (zip meta-2-blocks
              (tuple ;(slice meta-2-blocks 1)
                     {:field-info 0
                      :index math/inf
                      :inferences {}
                      :name-hash 0
                      :offset (get header :data-length)})))
    meta-2-blocks)

  (defn infere-field
    [meta-1-blocks
     field]
    (let [index               (get field :index)
          meta-1-entry-idx    (get field :meta-1-entry-idx)
          meta-1-block        (meta-1-blocks meta-1-entry-idx)
          num-direct-children (get meta-1-block :num-direct-children)
          num-all-children    (get meta-1-block :num-all-children)
          meta-2-entry-idx    (get meta-1-block :meta-2-entry-idx)
          is-object           (= index meta-2-entry-idx)]
      (put field :inferences (table :is-object is-object
                                    :num-direct-children (if is-object
                                                           num-direct-children
                                                           :null)))))

  (defn infere-fields-hierarchy
    ```
    Infere fields hierarchy by a stack, since the fields are laid out
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

      (defn infere-parent-field-index
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

      (loop [field :in fields]
        (infere-parent-field-index field)
        (decrease-last-num-remain-children)
        (remove-fulfilled-object)
        (if (and (get-in field [:inferences :is-object])
                 (pos? (get-in field [:inferences :num-direct-children])))
          (let [field-index         (get field :index)
                field-name          (get field :name)
                num-remain-children (get-in field [:inferences :num-direct-children])
                new-object          @{:field-index field-index
                                      :field-name field-name
                                      :num-remain-children num-remain-children}]
            (array/push objects-stack new-object)))))

    (defn infere-hierarchy-path
      [field &opt current-names]
      (default current-names @[])
      (if (= (field :index) 0)
        current-names
        (let [field-name (get field :name)
              parent-field-index (get-in field [:inferences :parent-field-index])
              parent-field (get fields parent-field-index)]
          (infere-hierarchy-path parent-field
                                 (array/push current-names field-name)))))

    (->> fields
         (map |(put-in $
                       [:inferences :hierarchy-path]
                       (reverse (infere-hierarchy-path $))))))

  (defn infere-field-data-type
    [field]

    (defn infere-field-data-type-hard-coded
      ```
      Infere field's data type by hard-coded hierarchy path since there is no
      special characteristic to infer the correct type.
      ```
      [field]
      (let [hierarchy-path (get-in field [:inferences :hierarchy-path])]
        (match hierarchy-path
          ["requirement_code"]                                       :char

          ["current_hp"]                                             :float
          ["m_Stress"]                                               :float
          ["actor" "buff_group" _ "amount"]                          :float
          ["chapter" _ _ "percent"]                                  :float
          ["non_rolled_additional_chances" _ "chance"]               :float

          ["read_page_index"]                                        :int-vector
          ["raid_read_page_indexes"]                                 :int-vector
          ["raid_unread_page_indexes"]                               :int-vector
          ["dungeons_unlocked"]                                      :int-vector
          ["played_video_list"]                                      :int-vector
          ["trinked_retention_ids"]                                  :int-vector
          ["last_party_guids"]                                       :int-vector
          ["dungeon_history"]                                        :int-vector
          ["buff_group_guids"]                                       :int-vector
          ["result_event_history"]                                   :int-vector
          ["dead_hero_entries"]                                      :int-vector
          ["additional_mash_disabled_infestation_monster_class_ids"] :int-vector
          ["mash" "valid_additional_mash_entry_indexes"]             :int-vector
          ["party" "heroes"]                                         :int-vector
          ["skill_cooldown_keys"]                                    :int-vector
          ["skill_cooldown_values"]                                  :int-vector
          ["bufferedSpawningSlotsAvailable"]                         :int-vector
          ["curioGroups" _ "curios"]                                 :int-vector
          ["curioGroups" _ "curio_table_entries"]                    :int-vector
          ["raid_finish_quirk_monster_class_ids"]                    :int-vector
          ["narration_audio_event_queue_tags"]                       :int-vector
          ["dispatched_events"]                                      :int-vector
          ["backer_heroes" _ "combat_skills"]                        :int-vector
          ["backer_heroes" _ "camping_skills"]                       :int-vector
          ["backer_heroes" _ "quirks"]                               :int-vector

          ["goal_ids"]                                               :string-vector
          ["quests" _ "goal_ids"]                                    :string-vector
          ["roaming_dungeon_2_ids" _ "s"]                            :string-vector
          ["quirk_group"]                                            :string-vector
          ["backgroundNames"]                                        :string-vector
          ["backgroundGroups" _ "backgrounds"]                       :string-vector
          ["backgroundGroups" _ "background_table_entries"]          :string-vector

          ["map" "bounds"]                                           :float-vector
          ["areas" _ "bounds"]                                       :float-vector
          ["areas" _ "tiles" _ "mappos"]                             :float-vector
          ["areas" _ "tiles" _ "sidepos"]                            :float-vector

          ["killRange"]                                              :two-int

          _                                                          :unknown
          )))

    (defn infere-field-data-type-heuristic
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
          (= raw-data-length 1) (let [byte (get-in field [:raw-data 0])]
                                  (if (and (>= 0x20 byte)
                                           (<= 0x7E byte))
                                    :char
                                    :bool))
          (and (= raw-data-length 8)
               (all |(or (= 0 $)
                         (= 1 $)) (map |(buffer->int $)
                                       (partition 4 raw-data)))) :two-bool
          (= raw-data-length 4) :int
          (and (>= raw-data-length 6)
               (= (slice raw-data 0 4) "\x01\xB1\0\0")) :file
          (>= raw-data-length 5) :string
          :unknown
          )))

    (-> field
        (get-in [:inferences :is-object])
        (|(case $
            true  :object
            :unknown))
        (|(case $
            :unknown (infere-field-data-type-hard-coded field)
            $))
        (|(case $
            :unknown (infere-field-data-type-heuristic field)
            $))))

  (defn infere-field-data
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

    (defn infer-string-vector
      [bytes]
      ```
      The bytes have this order:

        | n | m1 | data | \0 | m2 | data | \0 | ...

      Which means after having the length `n`, we have strings that are
      `m1`-character long, `m2`-character long, etc.

      For the actual work, we read `n`, and then repeat a process of reading
      `m`s and data `n` times.
      ```
      (let [fake-file (make-fake-file bytes)
            n (-> fake-file
                  (read-fake-file 4)
                  buffer->int)]
        (seq [_ :in (range n)]
          (-> fake-file
              (read-fake-file 4)
              (buffer->int)
              (|(read-fake-file fake-file $))
              (slice 0 -2) # the result string have a redundant `\0`
              ))))

    (let [data-type (get-in field [:inferences :data-type])
          raw-data  (field :raw-data-stripped)]
      (case data-type
        :char          raw-data
        :float         (buffer->float raw-data)
        :int-vector    (->> raw-data
                            (|(slice $ 4))
                            (partition 4)
                            (map buffer->int))
        :string-vector (infer-string-vector raw-data)
        :float-vector  (->> raw-data
                            (|(slice $ 4))
                            (partition 4)
                            (map buffer->float))
        :two-int       [(buffer->int raw-data)
                        (buffer->int (slice raw-data 4))]
        :bool          (= 1 (raw-data 0))
        :two-bool      [(= 1 (raw-data 0))
                        (= 1 (raw-data 1))]
        :int           (buffer->int raw-data)
        :file          (read-dson-bytes raw-data)
        :string        (slice raw-data 4 -2)
        :unknown
        )))

  (defn read-field
    [meta-2-block]
    (let [inferences (meta-2-block :inferences)
          index (meta-2-block :index)
          meta-1-entry-idx (inferences :meta-1-entry-idx)
          field-name-length (inferences :field-name-length)
          # `slice` from 0 to -2 is needed to strip the last character
          # since the string include "\0" at its tail
          field-name (slice (read-raw field-name-length)
                            0 -2)
          raw-data-length (inferences :raw-data-length)
          raw-data (read-raw raw-data-length)
          aligned-bytes (inferences :aligned-bytes)
          raw-data-stripped (if (> raw-data-length aligned-bytes)
                              (slice raw-data aligned-bytes)
                              raw-data)]
      (table :index index
             :meta-1-entry-idx meta-1-entry-idx
             :name field-name
             :name-hash (hash-dson-string field-name)
             :raw-data-length raw-data-length
             :raw-data raw-data
             :raw-data-stripped raw-data-stripped)))

  (defn read-fields
    [meta-1-blocks
     meta-2-blocks]
    (->> meta-2-blocks
         (map read-field)
         (map |(infere-field meta-1-blocks $))
         (infere-fields-hierarchy meta-1-blocks)
         (map |(put-in $
                       [:inferences :data-type]
                       (infere-field-data-type $)))
         (map |(put-in $
                       [:inferences :data]
                       (infere-field-data $)))
         ))

  (let [meta-1-blocks (read-meta-1-blocks (get header :num-meta-1-entries))
        meta-2-blocks (read-meta-2-blocks (get header :num-meta-2-entries))
        fields (read-fields meta-1-blocks
                            meta-2-blocks)]
    (table :header header
           :meta-1-blocks meta-1-blocks
           :meta-2-blocks meta-2-blocks
           :fields fields
           )))


(defn read-dson-file
  ```
  Read a Darkest Dungeon json file, decode it and return structured data.
  ```
  [path]
  (-> path
      (file/open :rb)
      (file/read :all)
      read-dson-bytes
      ))


(defn strip-blocks
  [dson-data key &opt len]
  (def blocks (get dson-data key))

  (default len (min 10 (length blocks)))
  (def len (min len (length blocks)))

  (merge-into dson-data
              @{key (slice blocks 0 len)
                (keyword (string key "-stripped-length")) len
                (keyword (string key "-full-length")) (length blocks)}))

(defn strip-meta-1-blocks
  [dson-data &opt len]
  (strip-blocks dson-data :meta-1-blocks len))

(defn strip-meta-2-blocks
  [dson-data &opt len]
  (strip-blocks dson-data :meta-2-blocks len))

(defn strip-fields
  [dson-data &opt len]
  (strip-blocks dson-data :fields len))

(defn skip-fields
  [dson-data &opt n]
  (update dson-data :fields |(skip $ n)))

(defn skip
  ```
  Skip the first `n` elements of a collection.
  ```
  [coll n]
  (case (type coll)
    :array (array/slice coll n)
    :tuple (tuple/slice coll n)
    (error "Not an indexed type!")))

# (def base-path "/home/thanh/.local/share/Steam/userdata/1036932376/262060/remote")
(def base-path (string (os/cwd) "/sample-data"))

(def file-names
  [
  "persist.upgrades.json"       # 0
  "persist.estate.json"         # 1
  "persist.roster.json"         # 2
  "persist.campaign_log.json"   # 3
  "persist.game_knowledge.json" # 4
  "persist.curio_tracker.json"  # 5
  "persist.game.json"           # 6
  "persist.campaign_mash.json"  # 7
  "persist.journal.json"        # 8
  "novelty_tracker.json"        # 9
  "persist.narration.json"      # 10
  "persist.town.json"           # 11
  "persist.quest.json"          # 12
  "persist.town_event.json"     # 13
  "persist.tutorial.json"       # 14
  "persist.progression.json"    # 15
  ])

(def paths
  (map |(string base-path "/" $)
       file-names))

(-> (paths 0)
    read-dson-file
    (strip-meta-1-blocks 3)
    (strip-meta-2-blocks 3)
    (skip-fields 50)
    (strip-fields 50)
    )

(-> (paths 13)
    read-dson-file
    (strip-meta-1-blocks 3)
    (strip-meta-2-blocks 3)
    (skip-fields 50)
    (strip-fields 50))

(def A @[1 2 3 4])
(put A 0 0)

# (slice "\x01\0\0\0\x14\0\0\0kill_drowned_crew_A\0" 8)
