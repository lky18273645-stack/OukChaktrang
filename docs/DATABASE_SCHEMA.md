# OukChaktrang.com – Database schema & architecture

The app is **100 % offline**, so everything is stored as JSON in the device
(`SharedPreferences`, key `ouk_ecosystem_v1`). The Dart models below map 1:1 to
Firestore documents or SQL rows, so a backend can be added later without
changing the game logic.

```
UI (screens)                      lib/screens, lib/widgets, lib/ui
   │  reads / calls
VirtualEcosystem (facade)         lib/services/virtual_ecosystem.dart
   │   users, bots, clubs, tournaments list, save/load
   ├── Glicko                     lib/services/glicko.dart            (ratings)
   ├── TnEngine / TnRules         lib/services/tournament_engine.dart (arena, swiss, rewards)
   └── profile_models             lib/services/profile_models.dart    (ratings per category, trophies, titles, history)
GameScreen ── result ──► reportTourneyGame() ──► TnEngine.reportUserMatch()
```

## Users  (`users/{uid}`)

```json
{
  "name": "Sokha", "cc": "KH", "bio": "Ouk Chaktrang lover", "flair": "🔥",
  "av": 7, "jm": 1763500000000, "fr": 0,
  "elo": 1275, "rd": 63.2,                      // headline rating (best played category)
  "cats": {                                     // one Glicko rating per time control
    "bullet": { "r": 1180.4, "rd": 98.1, "pk": 1201, "w": 3, "d": 0, "l": 4, "lp": 1763600000000 },
    "blitz":  { "r": 1275.0, "rd": 61.0, "pk": 1290, "w": 12, "d": 2, "l": 6, "lp": 1763600000000 },
    "rapid":  { "r": 1240.0, "rd": 70.4, "pk": 1260, "w": 8,  "d": 1, "l": 5, "lp": 1763600000000 },
    "daily":  { "r": 1200.0, "rd": 350,  "pk": 1200, "w": 0,  "d": 0, "l": 0, "lp": 0 }
  },
  "at": "ARENA KING",                           // title shown next to the name ("" = hidden)
  "aw": [                                       // earned titles (x = expiry ms, null = permanent)
    { "t": "ARENA KING", "id": "tn_1763...", "n": "Blitz Arena", "a": 1763600000000, "x": 1766192000000 }
  ],
  "tcase": [                                    // trophy case
    { "p": 1, "id": "tn_1763...", "n": "Blitz Arena", "f": "arena", "tc": "3+0", "d": 1763600000000 }
  ],
  "tw": 1,                                      // tournaments won
  "hist": [                                     // last 100 games
    { "id": "g1763...", "d": 1763600000000, "m": 3, "c": "blitz", "on": "Magnus Carlsen", "ot": "GM",
      "of": "🇳🇴", "oe": 2882, "s": 0.0, "dl": -2, "ac": 71.5, "rs": "checkmate", "tid": null }
  ]
}
```

Title rules (`TnEngine.rewardFor`): winner of an **Arena** → `ARENA KING` (valid 30
days), winner of a **Swiss** → `CHAMP` (permanent), the **3rd** tournament win → `CM`
(permanent). Needs ≥ 8 players and ≥ 1 game played. Top 3 get a trophy.

## Tournaments  (`tournaments/{id}`)

```json
{
  "id": "tn_1763600000000", "n": "Blitz Arena", "f": 0,         // 0 arena, 1 swiss
  "m": 3, "s": 1763600000000, "du": 1800000, "ro": 0, "c": 64,   // minutes, start, duration, rounds, capacity
  "cr": 1763599000000, "sd": 1763600000,                          // created, RNG seed (deterministic sim)
  "sc": 1763601500000, "cu": 0, "rs": 0,                          // sim clock, current round, round start
  "fi": false, "rw": false, "fm": 0                               // finished, rewards given, finished at
}
```

## Participants  (`tournaments/{id}/participants/{playerId}`)

```json
{ "id": "user", "n": "Sokha", "f": "🇰🇭", "t": "ARENA KING", "r": 1275, "u": true, "j": 1763600100000,
  "s": 8.0, "k": 3,                    // score, current win streak (fire when k >= 2)
  "g": 3, "w": 3, "d": 0, "l": 0, "b": 1,   // games, wins, draws, losses, berserks
  "bu": 0, "lo": "bot_17", "wd": false, "by": false, "o": ["bot_17"] }   // busy-until, last opp, withdrawn, had bye, opponents
```

## TournamentMatches  (`tournaments/{id}/matches/{matchId}`)

```json
{ "id": "tn_..._m42", "r": 0, "w": "user", "b": "bot_17", "s": 1763600200000, "e": 1763600420000,
  "ws": 1.0,                         // white score: 1 / 0.5 / 0 (null while being played)
  "bw": false, "bb": true, "p": 41, "a": true, "u": true }   // berserk white/black, plies, applied, user game
```

## Scoring

| Arena | points |
|---|---|
| Win / Draw / Loss | 2 / 1 / 0 |
| On fire (2+ wins in a row) | Win 4 / Draw 2 |
| Berserk (half clock) | +1 when you win a game of ≥ 7 moves |
| Draw shorter than 10 moves | 0 and the streak ends |

Swiss: 1 / ½ / 0, bye = 1, tie-break = Buchholz. Counting-rule draws
(ការរាប់ដង្ហើម) are ordinary late draws, so they score normally.

## SQL equivalent

```sql
CREATE TABLE users (uid TEXT PRIMARY KEY, name TEXT, country TEXT, bio TEXT, flair TEXT,
  joined_ms BIGINT, active_title TEXT, tournament_wins INT);
CREATE TABLE user_ratings (uid TEXT, category TEXT, rating REAL, rd REAL, peak INT,
  wins INT, draws INT, losses INT, last_played_ms BIGINT, PRIMARY KEY (uid, category));
CREATE TABLE user_titles (uid TEXT, title TEXT, tournament_id TEXT, awarded_ms BIGINT, expires_ms BIGINT);
CREATE TABLE trophies (uid TEXT, place INT, tournament_id TEXT, tournament_name TEXT, format TEXT,
  time_control TEXT, date_ms BIGINT);
CREATE TABLE match_history (id TEXT PRIMARY KEY, uid TEXT, date_ms BIGINT, minutes INT, category TEXT,
  opponent_name TEXT, opponent_title TEXT, opponent_elo INT, score REAL, delta INT, accuracy REAL,
  reason TEXT, tournament_id TEXT);
CREATE TABLE tournaments (id TEXT PRIMARY KEY, name TEXT, format TEXT, minutes INT, start_ms BIGINT,
  duration_ms BIGINT, rounds INT, capacity INT, seed INT, finished BOOLEAN, rewarded BOOLEAN);
CREATE TABLE participants (tournament_id TEXT, player_id TEXT, name TEXT, title TEXT, rating INT,
  score REAL, streak INT, games INT, wins INT, draws INT, losses INT, berserks INT,
  PRIMARY KEY (tournament_id, player_id));
CREATE TABLE tournament_matches (id TEXT PRIMARY KEY, tournament_id TEXT, round INT, white_id TEXT,
  black_id TEXT, start_ms BIGINT, end_ms BIGINT, white_score REAL, berserk_w BOOLEAN, berserk_b BOOLEAN,
  plies INT, applied BOOLEAN);
```
