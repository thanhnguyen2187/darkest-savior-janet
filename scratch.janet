(import ./darkest-savior/dson :fresh true)


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


(-> (paths 2)
    dson/read-file-bytes
    dson/decode-bytes
    dson/data->table
    protect
    )

(string/has-prefix? "two" :two)


