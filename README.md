# Monster Chase

**A free ride game for [S-Bike Training Hub](https://github.com/JHarp199345/S-Bike-Training-Hub).** Something is following you down a haunted forest path. Stay ahead, sprint or lean to dodge its lunge, and pedal hard to break free.

It's an interval workout in disguise: the monster's pace is set from your own FTP, it prowls and then surges every few minutes, and the path's hills set your trainer's resistance.

## Download

**[Download Monster Chase 0.1.17](https://github.com/JHarp199345/Monster-Chase/releases/latest)** (free). Needs S-Bike Training Hub 1.12.3 or later.

Monster Chase is not a standalone app. It runs inside the hub. Don't have the hub yet? [Install S-Bike Training Hub](https://github.com/JHarp199345/S-Bike-Training-Hub#set-it-up) first.

## Install

1. Download `monster-chase-0.1.17.zip` from the [Releases page](https://github.com/JHarp199345/Monster-Chase/releases/latest). Don't unzip it.
2. Open the hub and go to **Ride → Add a module**.
3. Drop in the ZIP. The hub shows you exactly what the game is allowed to read and control (listed below). Approve it.
4. Pick **Monster Chase** in the Ride menu and start pedalling.

The hub only installs games signed by the publisher and unchanged since signing, so a modified ZIP won't install.

## What the game can see and do

The hub enforces these limits; the game asks for nothing else.

| | |
|---|---|
| **Reads** | power, cadence, speed, your FTP, your weight |
| **Controls** | the trainer's hill, ride markers, lean steering |
| **Never sees** | your name, workouts, history, location, or anything else in the hub |

Leaning is optional: a tilted tablet, a phone on a rocker plate, your camera (head and shoulders only, processed on your device by the hub), or the arrow keys. The hub always decides what actually reaches your bike, and it clamps the hill to a safe range.

## Read the code

This repo holds the game's source code, exactly as shipped in 0.1.17, so you can check what it does.

| File | What it does |
|---|---|
| [`modes/monster_chase/monster_chase.gd`](modes/monster_chase/monster_chase.gd) | The game: the path, the monster, the lunge and dodge, the tug-of-war, the hills |
| [`core/hub_link.gd`](core/hub_link.gd) | The only connection to the hub: numbers in, requests out (start, set hill, mark, finish) |
| [`core/chase_pressure.gd`](core/chase_pressure.gd) | How hard the monster pushes, scaled to your FTP |
| [`core/rider_fit.gd`](core/rider_fit.gd), [`core/bike_fit.gd`](core/bike_fit.gd) | Putting the rider on the bike |
| [`pack-manifest.json`](pack-manifest.json) | The signed manifest: permissions, file fingerprints and signature |

The 3D models (bikes, riders, the monster) and the sky are not in this repo. Their licences allow them inside the game but not as separate downloads, so they're only in the signed ZIP. The game looks and plays exactly the same. Credits for every model are in [CREDITS.txt](CREDITS.txt).

## Credits

Built by JHarp199345 in Godot 4.7. Bikes by Semyon Filippov (CC BY 4.0), MatiDe and Maelstrow (CGTrader). Riders from Adobe Mixamo. The monster and the haunted forest sky were made with Sloyd. Full list: [CREDITS.txt](CREDITS.txt).

## Rights

Source shared so you can see what the game does. All rights reserved: please don't copy or republish the game or its code. The S-Bike Training Hub itself is [MIT licensed](https://github.com/JHarp199345/S-Bike-Training-Hub/blob/main/LICENSE).

Free to play. If you enjoy it, you can [buy me a coffee on Ko-fi](https://ko-fi.com/jharp199345). Also on [itch.io](https://jharp199345.itch.io/monster-chase).
