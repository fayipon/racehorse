# 視覺素材

## 觀眾歡呼音效

- 作者：Gregor Quendel；來源：[Free Crowd Cheering Sounds](https://opengameart.org/content/free-crowd-cheering-sounds)，授權 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)。
- 使用 10（Ambience）、05（Soft cheering - I）、03（Strong cheering - I）與 01（Strong cheering and strong rhythmic cheering），保存為 `public/audio/crowd/ambient.ogg`、`cheer.ogg`、`roar.ogg`。
- `scripts/prepare_crowd_audio.py` 擷取、濾除低頻、壓縮動態並製成無縫循環；高潮採兩段錄音的密集歡呼交疊，排除原檔安靜的頭尾。三層混音在末圈最後彎道前開始漸強，進彎至彎中自然升到高潮，持續經過衝線和整段結算，輸出有限幅器避免爆音。漸強使用實際跑道幾何、畫面時間與連續平滑曲線，進彎和衝線時不另行跳升音量。
- 完整來源、授權及修改說明保存在 `public/audio/crowd/LICENSE.txt`，頁尾提供署名連結。

## 賽事轉播語音

- 以 [Fish Audio](https://fish.audio) 的 S2.1 Pro 模型（`s2.1-pro-free`）生成。文字全為專案自寫（`scripts/commentary/<語言>.json`），由 `scripts/generate_commentary.py` 修剪、調整音量並合成 `public/audio/commentary/<語言>/voice.mp3`。使用依 Fish Audio 服務條款；免費模型的請求可能被用於改進模型，年營收超過 100 萬美元的產品需先聯繫 Fish Audio。
- 使用的公開聲音模型：
  - 普通話（繁中、簡中共用）：「影視解說」，ID `39ea63baf6c0480cb8148dc7955db78e`，作者暱稱 张磊。
  - 英文：「Sports commentary」，ID `f3199d67940c4ef3a029a5baf92ee8c2`，作者暱稱 cgpt80633。
  - 日文：「アツ実況」，ID `a8ac2a696ed54364952e415d40988775`，作者暱稱 BLUE。
  - 巴西葡文：「KAI」，ID `5626e9626f8c43b09edfff7467002114`，作者暱稱 Robert Ferreira Sousa。
- 點名第 9–12 號馬的台詞與十、十二匹的開閘句另存為各語言的 `voice-extra.mp3`，只有雷霆盃與皇家盃載入；陽光盃只載入 `voice.mp3`。
- 挑選聲音時排除了模仿真人（知名主持人、解說員）的聲音模型。
- 語氣參考 `design/` 內使用者提供的 Fish Audio 試驗音（中文與日文衝線口播），參考音本身不打包進網站。
- 先前以 `zh-TW-YunJheNeural` 生成的整句播報（`public/audio/announcer/`）已移除。

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

## 馬模型

### 比賽用：Viverna「Horses (Stallions)」（付費授權）

- 作者：Viverna；來源：[Fab – Horses (Stallions)](https://www.fab.com/listings/5f968a25-2177-433b-a8ae-ea6eea2926d9)，Fab 標準授權。
- **授權不允許散佈素材本身**，所以原始檔與處理後的檔案都不提交：購買下載的 `horses_blender292.zip`、`fbx_72.zip`、`tex.zip` 放在 `vendor/viverna/`，處理後的模型與貼圖在 `godot/assets/viverna/`，兩者都列在 `.gitignore`。只有匯出的遊戲（`public/game/index.pck`）含有它。
- 重建：`blender -b --factory-startup --python scripts/prepare_viverna_horse.py`。
  - 模型：取種馬的 LOD1（約 7,000 面，桌機）、LOD2（約 2,400 面，手機）、LOD3（780 面，只負責投影子）。
  - 動畫：取 6 段並改用比賽程式的名稱：Idle_1 → Idle、Idle_2、Idle_4 → Idle_Headlow、Eat → Eating、Walk、Gallop。每個動畫檔的骨架以該動畫第一格為靜止姿勢，和模型的綁定姿勢不同；直接套用會讓每個關節從錯的基準轉動（腳亂擺）。腳本逐格取出每根骨頭在骨架空間的位置，再以模型的靜止姿勢重新設定關鍵格，並檢查結果與原動畫一致。
  - 貼圖：5 種毛色（Black、Creame、Gray、GrayRose、White）與法線、鬃毛貼圖縮成 1024；材質參數圖（MADS）轉成 Godot 用的 ORM；以有損 WebP 匯入。
- `godot/scripts/asset_horse.gd` 的處理：
  - 放大 1.36 倍，和原本的馬一樣大（鼻尖到原點 2.2 米）。
  - 12 匹馬的毛色照 `horse_styles.json` 設定：栗色、棕色、金色由灰色或淡色貼圖染色（灰色貼圖的黑腿染成黑腳棕馬），黑、灰、白、雜色直接用原貼圖；鬃毛依設定色染色。
  - 號碼布依馬身橫切面自動貼合，並沿用馬身的骨架權重跟著身體動；冠軍花環依頸根的截面貼合。
  - **馬具**（2026-10-01，使用者說號碼布「挺假」）：號碼布上有一副皮革賽馬鞍（座墊、前鞍橋、後鞍橋、兩側鞍翼與車線），外面一條白色彈性外肚帶繞過鞍座與馬腹；鞍座、肚帶與號碼布同樣依馬身貼合、用同一組骨架權重。號碼布下緣略離開馬身，四邊有約 1.2 公分的布厚，走動與奔跑時下擺隨步伐擺動（奔跑時較大）。
  - 號碼布、鞍座、肚帶都由 `godot/shaders/saddle_cloth.gdshader` 畫出（`part` 0／1／2）：號碼布是棉斜紋布、下擺有自然皺褶、同色系的細滾邊與車線、圓角下緣，鞍座四周的布被壓出陰影，號碼印在兩側布面上。布面座標以公尺計，換模型時細節大小不變。號碼取自 `godot/assets/cloth_digits.png`（Godot 預設字型渲染的 0–9），可用 `godot --path godot -s res://tools/bake_cloth_digits.gd` 重建（需開視窗）。馬具不投影，馬身的影子由 LOD3 投出。
  - 冠軍花環是一圈紅玫瑰（少數白玫瑰）綁在綠葉繩上，每朵三層花瓣、兩片葉子，朝向馬頭。
  - 走路依馬實際移動的距離推進（每個循環 1.39 米，量自著地蹄不滑動的速度），蹄不會在地上滑。奔跑維持賽馬的節奏：賽道約為實際的三分之一大，馬群只跑 6–7 m/s，若照地面速度播放，種馬 6.4 米的步幅每秒只跨一步、像慢動作；所以在一般速度下每秒約 2.1 步，速度越快略為加快（`GALLOP_TEMPO`、`GALLOP_PACE`）。
  - **步幅貼合地面**（2026-10-01，使用者要求跑步更真實）：以賽馬節奏播放襲步時，著地的蹄子會以每秒 5～8 米在草地上滑行。`godot/scripts/stride_fit.gd` 是骨架修正器（SkeletonModifier3D），在動畫套上之後，依當下速度與播放速率把每條腿的前後擺幅收窄到著地的蹄子剛好不動（約為原本的 0.35～0.55），保留蹄子高度，用兩段 IK 彎曲膝或肘，蹄子維持動畫的角度。等於這個速度下真實馬用的短而快的步伐。滑動降到約每秒 0.4～1.7 米（多半是落地、離地瞬間）。每匹馬每幀約 10 微秒。各腿的擺幅中心與著地掃動速度在第一匹馬建立時從襲步動畫取樣一次。
  - **動畫開頭的重複幀**：模型包的每支動畫第 0、1 幀是同一個姿勢，循環時每步會卡一幀。`asset_horse.gd` 的 `trim_held_frame` 在載入時剪掉第一幀（只在偵測到重複時），襲步改為 20 幀、走路 31 幀。
  - **彎道**：依速度乘轉向角速度算出向心力，身體向內側傾斜（最多約 11°，彎道上約 8～10°），頸部同時轉向彎道內側。
  - **衝線姿勢**：冠軍最後約 1.6 秒會微調步伐節奏（最多 ±30%），讓衝線停格時剛好是前腿向前伸展、後腿向後蹬的姿勢，不會停在四腿收在腹下的瞬間。
- 沒有這批素材時（例如從公開 repo clone），自動改用下方的 CC0 馬；也可用 `-- --cc0-horse` 參數強制使用。

### 備援：Quaternius 馬（CC0）

- 作者：Quaternius。
- 來源：[Horse on Poly Pizza](https://poly.pizza/m/qvTrSG9pZF)。
- 授權：CC0 1.0，來源與授權連結保存在 `godot/assets/quaternius/LICENSE.md`。
- 檔案：`godot/assets/quaternius/horse.glb`，保留下載原檔。
- 選馬卡片使用 `public/assets/horse-1.png` 至 `horse-12.png`，由 `scripts/render_horse_portraits.gd` 直接渲染目前的 3D 模型、自然毛色與號碼布，原圖集保留供參考。
- 結算的前三名橫幅使用 `public/assets/horse-band-1.webp` 至 `horse-band-12.webp`，大廳使用 `horse-head-1.webp` 至 `horse-head-12.webp`，都由 `scripts/render_horse_heads.gd` 從同一個 3D 模型渲染（`godot --path godot -s ../scripts/render_horse_heads.gd`）。橫幅圖寬 1.5 倍：用偏移的視錐讓頭部維持同樣構圖，右側接著畫出脖子、號碼布與身體，所以馬身延伸到橫條邊緣，不會被方框切斷；大廳的頭像取自其左側正方形。

## 自然植栽素材

- **樹、灌木、草叢**（2026-10-01 重製，使用者給參考圖、要求寫實且遠近有層次，並要風吹搖動）：全部由 `scripts/bake_trees.py` 自己長出來，不用照片或外部模型，輸出到 `godot/assets/trees/`。
  - 樹：四種（橡樹 12.9 m、榆樹 15.3 m、圓冠 10.1 m、小樹 7.1 m）。枝幹用空間殖民演算法朝樹冠裡散布的吸引點生長，粗細依管線模型（每段承載它供養的所有枝條），樹冠是一圈分開的葉團、中間露出天空與枝幹。樹葉是貼著細枝的葉片卡，貼圖是程式畫的葉叢（`leaves.png` 2×2：兩種樹葉叢、灌木葉、開黃花的灌木）。頂點色存環境光遮蔽，葉片法線指向所屬葉團外側，整團樹冠像一個柔和的體積受光。
  - 灌木兩種、草叢兩種（`grass.png`）。
  - 遠排的樹用看板（impostor）：`godot/tools/bake_impostors.gd`（需開視窗）把每棵樹拍成正面顏色圖與法線圖，`impostor.gdshader` 讓看板轉向鏡頭並用法線打光；陰影階段看板轉向太陽，投出樹的剪影。
  - 層次由近到遠：內場小樹林與外圍第一排（桌機 3D、手機看板）→ 第二排與外圈樹叢（看板）→ 168～200 m 三排連續林帶（前排有低矮灌叢遮住樹幹）→ 兩圈森林山脊（`hills.gdshader`：樹冠斑紋、草地空地、越遠越藍的空氣透視）。
  - **風**：樹、灌木、草叢由地面起彎曲，傾斜量隨高度平方增加，陣風沿風向掃過全場，鄰近的植物一起動，葉片另有細碎抖動；樹幹和樹冠用同一組參數一起彎。遠排看板與跑道草葉（草殼）也跟著同一陣風。玩家開了「減少動態」就全部靜止。參數在 `flora.gd` 的 `WIND`。
  - 樹籬改用葉片貼圖三面投影（`foliage.gdshader` 的 `leafy`）。
- [Quaternius Stylized Nature MegaKit](https://quaternius.com/packs/stylizednaturemegakit.html) 免費模型已全部不用：樹、灌木、草叢由上面取代，花叢與石頭隨 2026-10-01 內場改版移除。模型保留，整個 `assets/nature/` 由 `export_presets.cfg` 排除，不打包（遊戲包 8.3 → 8.0 MB）。
- 由作者的 [Poly Pizza 素材集](https://poly.pizza/bundle/Stylized-Nature-MegaKit-T34GZFA0fm) 取得，授權 CC0；各模型來源與原始 SHA-256 記錄於 `godot/assets/nature/manifest.json`，授權說明於同目錄 `LICENSE.md`。
- 模型重新封裝為 glTF／BIN，共用相同的原始貼圖，未改動模型幾何或貼圖像素。重建工具：`scripts/prepare_nature_assets.py`。
- `godot/scripts/landscape.gd` 負責分群種植與 MultiMesh 空間批次；`foliage.gdshader`／`ground.gdshader` 為專案自製風動與草地材質，未使用付費版 Shader。

## 看台與觀眾素材

- 主看台、大螢幕、帳篷、旗桿與陽傘由 `venue.gd` 以 `mesh_kit.gd` 程序生成，不使用外部建築模型。
- **建築材質**（2026-10-01，使用者說看台質感低）：看台、起跑閘門、領獎台共用自製的 `godot/shaders/structure.gdshader`，一個結構一次繪製。頂點色是顏色，頂點色的 alpha 標記材料（`mesh_kit.gd` 的 `PAINT`、`CONCRETE`、`GLAZING`、`METAL`、`SEAT`、`PAVING`、`CANVAS`、`RUBBER`、`GOLD_LEAF`、`DAMASK`、`MARBLE`、`PADDING`，用 `KIT.made_of(顏色, 材料)` 標）：烤漆、清水混凝土（骨材、雨痕）、玻璃（玻璃後面有房間：天花板筒燈、牆、吧台、人影、半拉的百葉窗，用視線在房間盒子裡的交點畫出，不需要模型）、拉絲金屬、座椅塑膠、鋪面石板、帆布（透光）、橡膠、金箔、緞紋壁布、大理石（雲紋與細脈）、直條車縫軟墊。細節都以世界座標計，構件相接處不會有接縫。新的構件幾何有 `KIT.rounded_box`（倒角方塊）、`KIT.extrude`（輪廓擠出）、`KIT.loft`（沿封閉路徑掃出斷面）、`KIT.sphere`、`KIT.ellipsoid`。
- **主看台**：地面層是混凝土圓柱拱廊與玻璃大廳；十排預鑄看台有倒角踏面、走道階梯與扶手，每個座位是一張綠色模壓座椅（手機省略座椅）；前緣玻璃欄板配不鏽鋼扶手；包廂是白色鰭板間的玻璃；懸挑屋頂下有肋條與燈光感的天花板，屋頂上九道弓形鋼桁架，桁架頂各有一支旗桿；盃賽徽牌掛在屋頂前緣。觀眾衣著改成看賽馬的配色（白、海軍藍、黑、灰、卡其為主，少量彩色），腿部與座位處較暗。
- **旗子**（使用者說旗子不會隨風飄、很假）：每面旗是 18×7 格的布面網格，`godot/shaders/flag.gdshader` 讓波浪從旗桿往旗尾傳、越往尾端越大，法線跟著布面斜率走（皺褶有明暗），陽光從背面透過；風向與陣風和樹木同一組（`foliage.gdshader` 的 `WIND`），陣風弱時旗尾垂下。「減少動態」時只剩微小擺動。
- 帳篷改帆布材質、屋面微凹、圓弧垂邊；陽傘加綠色垂邊與金色頂飾。
- 先前使用的 [Kenney Racing Kit 2.0](https://kenney.nl/assets/racing-kit) 看台與設施（CC0）原始 OBJ／MTL 與 License.txt 保留在 `godot/assets/venue/kenney/` 供參考，已由 `export_presets.cfg` 排除，不打包進 Web 匯出。
- 觀眾採用 [Quaternius Background Posed Humans](https://quaternius.com/packs/backgroundposedhumans.html)，從[作者在 OpenGameArt 的發布頁](https://opengameart.org/content/lowpoly-posed-humans)取得完整素材包。使用男女坐姿、坐姿加油、站立揮手與四種髮型，授權 CC0；原始 OBJ／MTL 與作者授權檔保存在 `godot/assets/venue/crowd/`。
- `godot/assets/venue/manifest.json` 記錄素材來源、壓縮檔及所保留原始檔的 SHA-256。作者的授權檔原樣保留（檔內標頭寫 Knight Pack，但內文署名為 Background characters，發布頁亦明確標示 CC0）。
- `venue.gd` 依主看台的座位排數與走道排列觀眾，合併人物與髮型並以 MultiMesh 分批繪製；衣服／膚色由自製 `spectators.gdshader` 隨機配置，保留原模型姿勢。
- 遠景山丘（2026-10-01 起）：`landscape.gd` 以雜訊生成兩圈環狀地形（222～282 m、320～455 m），`hills.gdshader` 畫森林樹冠斑紋與空地，越遠的一圈霧氣越重、越藍。取代原本拉寬的石頭模型。

## 草地跑道、欄杆與內場

- `godot/scripts/race_track.gd` 程序生成草地跑道、沙地訓練道、白色圓管欄杆（內欄鵝頸柱）、終點柱、距離桿與樹籬；材質為自製 `ground`（草皮、沙道）與 `foliage`（樹籬）shader；同類表面共用一個 shader，以減少 Web 首次載入的編譯時間。未使用付費跑道素材。
- **寫實草皮**（2026-10-01，使用者給參考圖要求「真實草皮」）：
  - 貼圖由 `scripts/bake_turf.py` 自己畫出來（隨機草葉與沙粒，沒有用照片或外部素材），可無縫拼接，放在 `godot/assets/turf/`：草皮 1 米一格的顏色（1024）與法線（512）、沙道 3 米一格的耙痕與蹄印（顏色 1024、法線 512）。匯入為有損 WebP，整組約 1.2 MB。
  - 草皮、內場、外圍草地、頒獎台都用 `mesh_kit.gd` 的 `KIT.ground(pattern, 暗色, 亮色)` 建材質：貼圖給草葉細節，兩個顏色決定各區的色調；另外疊兩層放大、旋轉的同一張貼圖，打散重複並保留中距離的草叢紋理。
  - 割草條紋改為沿跑道方向（跟著彎道），明暗隨觀看方向翻轉：草葉倒向遠離鏡頭的那條偏亮、倒向鏡頭的偏暗，從正上方看幾乎看不出來。
  - 近景草葉：桌機在跑道上疊 12 層「草殼」，每層只留長得到那個高度的草葉，草葉順著條紋方向傾斜，欄杆邊的草較長。草葉小於約一個像素就逐漸縮回貼圖裡，避免閃爍；草殼切成 28 段，只畫鏡頭 26 米內的段，額外 GPU 成本很小。手機（`low_power`）不畫草殼，只用貼圖。
  - 跑道內欄一側有馬蹄踩出的偏黃磨損帶與零星草皮翻起的土坑。
- **欄杆細節**（2026-10-01，使用者指出立柱接頭粗糙）：欄杆是 `KIT.sweep` 沿整圈掃出的一條圓管（桌機 16 面、手機 10 面），相鄰段共用頂點、方向沿路延續，沒有接縫或扭轉。內欄鵝頸柱的頸部是一段平滑彎臂，從內場側水平接進欄杆；外欄與沙道欄杆的直立柱停在最上面那條欄杆的中心裡。每個接點都有 `KIT.collar` 做的模壓套管（端面倒角、圓角法線），立柱入土處有底座套管。
- **內場**（2026-10-01，使用者說內圈裝飾很土氣、不一定要這些東西）：拿掉噴泉、造型馬與花石點綴，改成像公園的內場。`godot/scripts/infield.gd` 建立斜格草坪、中線上一座細長的靜水湖（石材壓頂、`water.gdshader` 反映天空、深色湖水與岸邊淺水、細小的風紋）、沙道內側一整圈修剪的黃楊樹籬，以及湖兩側四塊地毯式花壇（紅、白、白、金，`ground.gdshader` 的 pattern 4：密生的五瓣小花，遠看融成花壇的顏色），各圍一圈矮樹籬。`landscape.gd` 只在兩端彎道與湖邊種幾組成樹，樹下有修剪灌木。
- **起跑閘門**（2026-10-01，使用者說閘門也不行）：`starting_gate.gd` 改成真實閘門的構造：綠色鋼管框架、前後兩道三角桁架橫樑、底部滑軌、各閘間的直條車縫軟墊隔板、上方開放欄杆；前門下半是軟墊、上半是鋼條，前門色帶與閘位號碼牌（白框）用各號馬的顏色；兩端塔架有斜撐，掛在兩組充氣輪胎上。尺寸常數、開門方式與測試不變。手機版管件面數較少，前門不投影。
- **領獎台**（使用者要求一起優化）：`podium.gd` 改成拋光大理石台階（金邊飾條、金框深綠名次牌）、鑲金環的大理石圓地坪、往鏡頭延伸的紅毯；後方弧形牆是深綠緞紋壁布配大理石壁柱、金色柱頭、金框牆板與大理石簷口，中間掛 WINNER 金框徽牌，牆腳一排紅白花壇；另有兩盞洗牆燈。牆越往上越暗，疊在上面的標題仍有對比。
- 先前的欄杆模型：3D Assets 的 [Horse Stables and Equestrian Yard — Arena Rail](https://3dassets.dev/assets/equestrian-yard-and-stables-arena-rail-2d66cd48)（CC0 1.0，發布者標示為 AI 製作素材）。原始與轉換後的 GLB、`manifest.json`、`LICENSE.md` 保留在 `godot/assets/equestrian/` 供參考，`scripts/prepare_equestrian_assets.mjs` 仍可重建；現已由 `export_presets.cfg` 排除，不打包進 Web 匯出。
- 馬蹄後的粒子調整為較小、較淡的草綠色揚屑，取代原本沙地的黃褐色塵霧。2026-10-01 起另有踢起的草皮土塊（深褐土塊、頂上帶草），每步沿短拋物線往後飛、落回草地；全場一批 MultiMesh，與欄杆柱共用同一個 shader，手機減半，減少動態時不顯示。

## 保留的原程式模型

`godot/assets/pony_body.obj` 與 `pony_head.obj` 由 `scripts/sculpt_pony.py` 以平滑融合橢球與 marching tetrahedra 建構。`godot/shaders/knit.gdshader` 程序產生針織表面，不依賴外部模型或貼圖服務。這些為專案內生成的 3D 幾何，不是生成圖片的平面替代。`pony.gd`、兩個 OBJ、`knit.gdshader` 與未使用的 `sunny_sky.gdshader` 由 `godot/export_presets.cfg` 的 `exclude_filter` 排除，不打包進 Web 匯出；`godot/tests/` 同樣不匯出。

## 實拍天空

- [Kloppenheim 05 (Pure Sky)](https://polyhaven.com/a/kloppenheim_05_puresky)，Poly Haven。
- 作者：Greg Zaal（原始攝影）、Jarod Guest（純天空編修）。授權：[CC0](https://polyhaven.com/license)。
- 使用官方 8K Tonemapped JPG 全景素材，保留原檔於 `godot/assets/sky/`，Godot 匯入時限制為 4096 像素並壓縮，不修改原始照片。
- PanoramaSkyMaterial 取代自製雲朵與太陽 Shader，使用照片本身的光線、雲層及太陽。
