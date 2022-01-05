(import ../darkest-savior/dson)


(def file-names
  [
  "novelty_tracker.json"        # 0
  "persist.campaign_log.json"   # 1
  "persist.campaign_mash.json"  # 2
  "persist.curio_tracker.json"  # 3
  "persist.estate.json"         # 4
  "persist.game.json"           # 5
  "persist.game_knowledge.json" # 6
  "persist.journal.json"        # 7
  "persist.narration.json"      # 8
  "persist.progression.json"    # 9
  "persist.quest.json"          # 10
  "persist.roster.json"         # 11
  "persist.town.json"           # 12
  "persist.town_event.json"     # 13
  "persist.tutorial.json"       # 14
  "persist.upgrades.json"       # 15
  ])

(def base-path
  (string (os/cwd)
          "/sample-data"))

(def paths
  (map |(string base-path "/" $)
       file-names))


(defn test-path
  [path]
  (let [dson-data (-> path
                      dson/read-file-bytes
                      dson/decode-bytes)]

    # make sure that the magic numbers are correct
    (-> dson-data
        (get-in [:header :magic-number])
        (= "\x01\xB1\0\0")
        assert)

    # make sure that there is exactly 64 bytes within the header
    (-> dson-data
        (get :header)
        values
        (|(map (fn [item]
                 ```
                 Return 4 bytes as the bytes count of an integer.
                 Return `length` of others.
                 ```
                 (if (number? item)
                   4
                   (length item)))
               $))
        sum
        (= 64)
        assert)
    ))

(map test-path paths)

(test-path (paths 1))

(map length ["one two" "three four"])

(protect (+ 1 1))
