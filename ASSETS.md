# 視覺素材

## 觀眾歡呼音效

- 作者：Gregor Quendel；來源：[Free Crowd Cheering Sounds](https://opengameart.org/content/free-crowd-cheering-sounds)，授權 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)。
- 使用 10（Ambience）、05（Soft cheering - I）、03（Strong cheering - I）與 01（Strong cheering and strong rhythmic cheering），保存為 `public/audio/crowd/ambient.ogg`、`cheer.ogg`、`roar.ogg`。
- `scripts/prepare_crowd_audio.py` 擷取、濾除低頻、壓縮動態並製成無縫循環；高潮採兩段錄音的密集歡呼交疊，排除原檔安靜的頭尾。三層混音在末圈最後彎道前開始漸強，進彎至彎中自然升到高潮，持續經過衝線和整段結算，輸出有限幅器避免爆音。漸強使用實際跑道幾何、畫面時間與連續平滑曲線，進彎和衝線時不另行跳升音量。
- 完整來源、授權及修改說明保存在 `public/audio/crowd/LICENSE.txt`，頁尾提供署名連結。此音效取代目前直播主播與電子提示音。

## 生成的視覺素材

使用內建 imagegen 製作；圖片均已複製到專案，程式不依賴 Codex 暫存位置。

- `public/assets/horses.png`：八匹絨毛小馬的 4×2 肖像圖集，用於選馬卡片。
- `public/assets/track.png`：暖色賽場背景，原用於引擎載入畫面；現行畫面改用純色底，不再引用，保留供參考。

## 最終採用提示詞

### 小馬圖集

Use case: stylized-concept. Asset type: transparent sprite sheet for a playable plush horse racing game. Generate exactly EIGHT separate cute knitted plush toy horses in a perfectly aligned 4 columns by 2 rows grid, each cell equal sized, no overlaps, generous transparent margin between horses. TRUE transparent background. Each horse is a full body, same scale, shown in a side / slight three quarter view facing RIGHT, a galloping pose with four stubby legs, round chunky body, big snout, tiny shiny black eyes, yarn mane and tail, tactile crochet texture, beautiful polished 3D toy render warm sunshine. Top row colors left to right: coral red, sage green, golden yellow, lavender purple. Bottom row left to right: orange, candy pink, sky cyan, cobalt blue. No riders, no text, no numbers, no harness, no shadow outside the horse. Each fits wholly within its equal rectangular cell with plenty of margin. Landscape 1536x1024. High quality toy game assets, adorable like a stop motion film.

### 賽場

Use case: stylized-concept. Asset type: panoramic background for a cute plush horse race video game. Wide landscape 1536x1024. A beautiful warm sunlit horse racing stadium, viewed slightly elevated from the side, looking across the track. Entire LOWER 70 percent is an EMPTY broad terracotta sandy horizontal straight racing track with subtle grooming streaks that goes from left edge to right edge, NO horses, no animals, no people on track, no text, no UI. At the top 30 percent: white track railing, short green hedge, distant grandstands filled with soft colorful spectators, trees, pennant flags, blue sky, golden afternoon light. Polished 3D animation movie / cozy miniature diorama aesthetic, warm charming colorful art direction, realistic sand texture and soft depth of field in the distant stands. On the very bottom edge a thin white track rail and strip of green grass framing the track, main track must remain unobstructed to overlay eight animated horses. Track stretches straight horizontally across entire image, not oval, no central grass island, no finish line, no numbers or logos. Medium broad shot, appealing sunlight, high quality game environment.

3D 比賽中的馬採用下方現成骨架模型，可即時移動與切換攝影機。使用者的影片只用作流程、鏡頭參考，不是預錄賽果。

## 目前試用的現成馬模型

- 作者：Quaternius。
- 來源：[Horse on Poly Pizza](https://poly.pizza/m/qvTrSG9pZF)。
- 授權：CC0 1.0，來源與授權連結保存在 `godot/assets/quaternius/LICENSE.md`。
- 檔案：`godot/assets/quaternius/horse.glb`，保留下載原檔。
- `godot/scripts/asset_horse.gd` 調整比例、朝向、自然馬色、原八色識別，以及跟隨背部骨架的一整片號碼布，使用原檔內的 Idle / Walk / Gallop 動畫並平滑切換。
- 選馬卡片使用 `public/assets/horse-1.png` 至 `horse-8.png`，由 `scripts/render_horse_portraits.gd` 直接渲染目前的 3D 模型、自然毛色與號碼布，原圖集保留供參考。

## 自然植栽素材

- 採用 [Quaternius Stylized Nature MegaKit](https://quaternius.com/packs/stylizednaturemegakit.html) 免費模型：五種闊葉樹、兩種灌木、三種草叢、兩種花叢、兩種石頭。
- 由作者的 [Poly Pizza 素材集](https://poly.pizza/bundle/Stylized-Nature-MegaKit-T34GZFA0fm) 取得，授權 CC0；各模型來源與原始 SHA-256 記錄於 `godot/assets/nature/manifest.json`，授權說明於同目錄 `LICENSE.md`。
- 模型重新封裝為 glTF／BIN，共用相同的原始貼圖，未改動模型幾何或貼圖像素。重建工具：`scripts/prepare_nature_assets.py`。
- `godot/scripts/landscape.gd` 負責分群種植與 MultiMesh 空間批次；`foliage.gdshader`／`meadow.gdshader` 為專案自製風動與草地材質，未使用付費版 Shader。

## 看台與觀眾素材

- 主看台、大螢幕、帳篷、旗桿與陽傘由 `venue.gd` 以 `mesh_kit.gd` 程序生成，不使用外部建築模型。
- 先前使用的 [Kenney Racing Kit 2.0](https://kenney.nl/assets/racing-kit) 看台與設施（CC0）原始 OBJ／MTL 與 License.txt 保留在 `godot/assets/venue/kenney/` 供參考，已由 `export_presets.cfg` 排除，不打包進 Web 匯出。
- 觀眾採用 [Quaternius Background Posed Humans](https://quaternius.com/packs/backgroundposedhumans.html)，從[作者在 OpenGameArt 的發布頁](https://opengameart.org/content/lowpoly-posed-humans)取得完整素材包。使用男女坐姿、坐姿加油、站立揮手與四種髮型，授權 CC0；原始 OBJ／MTL 與作者授權檔保存在 `godot/assets/venue/crowd/`。
- `godot/assets/venue/manifest.json` 記錄素材來源、壓縮檔及所保留原始檔的 SHA-256。作者的授權檔原樣保留（檔內標頭寫 Knight Pack，但內文署名為 Background characters，發布頁亦明確標示 CC0）。
- `venue.gd` 依主看台的座位排數與走道排列觀眾，合併人物與髮型並以 MultiMesh 分批繪製；衣服／膚色由自製 `spectators.gdshader` 隨機配置，保留原模型姿勢。
- 遠景山丘由現有 Nature MegaKit 石頭模型拉寬、壓低並分層排列，使用低對比霧色材質。

## 草地跑道、欄杆與內場

- `godot/scripts/race_track.gd` 程序生成草地跑道、沙地訓練道、白色圓管欄杆（內欄鵝頸柱）、終點柱、距離桿與樹籬；材質為自製 `racing_turf`、`dirt_track`、`hedge` shader。修剪條紋沿橢圓連續銜接，近景有細微紋理、遠景降低細節以減少閃爍。未使用付費跑道素材。
- `godot/scripts/infield.gd` 與自製 `lawn`、`water`、`hedge` shader 建立內場斜格草坪、噴泉池與造型馬花園；造型馬沿用 Quaternius 馬模型，套上樹籬材質。噴泉以 CPUParticles3D 繪製。冠軍圈的盆栽樹沿用 Nature MegaKit 的 `tree_round`。
- 先前的欄杆模型：3D Assets 的 [Horse Stables and Equestrian Yard — Arena Rail](https://3dassets.dev/assets/equestrian-yard-and-stables-arena-rail-2d66cd48)（CC0 1.0，發布者標示為 AI 製作素材）。原始與轉換後的 GLB、`manifest.json`、`LICENSE.md` 保留在 `godot/assets/equestrian/` 供參考，`scripts/prepare_equestrian_assets.mjs` 仍可重建；現已由 `export_presets.cfg` 排除，不打包進 Web 匯出。
- 馬蹄後的粒子調整為較小、較淡的草綠色揚屑，取代原本沙地的黃褐色塵霧。

## 保留的原程式模型

`godot/assets/pony_body.obj` 與 `pony_head.obj` 由 `scripts/sculpt_pony.py` 以平滑融合橢球與 marching tetrahedra 建構。`godot/shaders/knit.gdshader` 程序產生針織表面，不依賴外部模型或貼圖服務。這些為專案內生成的 3D 幾何，不是生成圖片的平面替代。`pony.gd`、兩個 OBJ、`knit.gdshader` 與未使用的 `sunny_sky.gdshader` 由 `godot/export_presets.cfg` 的 `exclude_filter` 排除，不打包進 Web 匯出；`godot/tests/` 同樣不匯出。

## 實拍天空

- [Kloppenheim 05 (Pure Sky)](https://polyhaven.com/a/kloppenheim_05_puresky)，Poly Haven。
- 作者：Greg Zaal（原始攝影）、Jarod Guest（純天空編修）。授權：[CC0](https://polyhaven.com/license)。
- 使用官方 8K Tonemapped JPG 全景素材，保留原檔於 `godot/assets/sky/`，Godot 匯入時限制為 4096 像素並壓縮，不修改原始照片。
- PanoramaSkyMaterial 取代自製雲朵與太陽 Shader，使用照片本身的光線、雲層及太陽。
