// ============================================================
// Dastarkhwan waiting-room game — 2-player football
// ------------------------------------------------------------
// This is the uploaded "2D-2Player-Football" game (Phaser 3 arcade
// physics), with its original Node/socket.io networking layer swapped
// for Supabase Realtime (broadcast + presence) — since this app has no
// standalone game server, only Supabase. The actual game logic
// (movement, kicking, scoring) is kept as close to the original as
// possible; only the networking plumbing changed.
//
// Presence assigns player 1 / player 2 by join order (first device to
// join this table's game channel is Player 1). A third device that
// scans the same table sees a "match is full" spectator message
// rather than breaking the game for the first two.
// ============================================================

(function () {
  const params = new URLSearchParams(window.location.search);
  const sessionKey = params.get("session") || "default-table";
  const restaurantName = params.get("name") || "";
  const myId = getDeviceId();

  // Sizing — original sprites are small (32x48 players, 32x32 ball) at
  // this game's 800x600 resolution. Scaled up so they're easy to see
  // and hit on a phone: players end up roughly half the goal's height,
  // the ball a bit bigger without feeling cartoonish.
  const PLAYER_SCALE = 2.8;
  const BALL_SCALE = 1.6;

  // ---------------------------------------------------------------
  // Networking shim — gives Phaser scenes the same socket.io-shaped
  // API (`on`, `emit`, `.id`) the original game was written against,
  // backed by a Supabase Realtime channel instead of a socket server.
  // ---------------------------------------------------------------
  class RealtimeShim {
    constructor(id) {
      this.id = id;
      this.listeners = {};
      this.players = {}; // id -> {playerId, index}
      this.myIndex = null;
      this.ready = false;

      this.channel = supa.channel(`game:${sessionKey}`, {
        config: { presence: { key: id } },
      });

      this.channel.on("broadcast", { event: "msg" }, ({ payload }) => {
        if (!payload || payload.from === this.id) return;
        this._fire(payload.type, payload.data);
      });

      this.channel.on("presence", { event: "sync" }, () => this._syncPresence());
      this.channel.on("presence", { event: "leave" }, ({ key }) => {
        if (this.players[key]) {
          const info = this.players[key];
          delete this.players[key];
          this._fire("disconnect", info.playerId);
        }
      });

      this.channel.subscribe((status) => {
        if (status === "SUBSCRIBED") {
          this.channel.track({ id: this.id, joinedAt: Date.now() });
        }
      });
    }

    _syncPresence() {
      const state = this.channel.presenceState();
      const entries = Object.keys(state).map((key) => {
        const meta = state[key][0];
        return { id: key, joinedAt: meta.joinedAt || 0 };
      });
      entries.sort((a, b) => a.joinedAt - b.joinedAt);

      const wasReady = this.ready;
      const previousIds = Object.keys(this.players);

      this.players = {};
      entries.slice(0, 2).forEach((e, i) => {
        this.players[e.id] = { playerId: e.id, index: i };
        if (e.id === this.id) this.myIndex = i;
      });

      this.tooCrowded = entries.length > 2 && this.myIndex === null;

      const newIds = Object.keys(this.players);
      const isNewJoin = newIds.some((id) => !previousIds.includes(id));

      if (newIds.length >= 1) {
        this._fire("currentPlayers", { ...this.players });
      }
      if (isNewJoin && wasReady) {
        // Someone joined after we already had our own player set up —
        // tell the scene directly (mirrors the original 'newPlayer' event).
        newIds
          .filter((id) => id !== this.id && !previousIds.includes(id))
          .forEach((id) => this._fire("newPlayer", this.players[id]));
      }
      this.ready = true;
    }

    on(event, cb) {
      (this.listeners[event] = this.listeners[event] || []).push(cb);
    }

    emit(event, data) {
      this.channel.send({ type: "broadcast", event: "msg", payload: { type: event, data, from: this.id } });
    }

    _fire(event, data) {
      (this.listeners[event] || []).forEach((cb) => cb(data));
    }
  }

  // ---------------------------------------------------------------
  // Touch controls — a virtual cursor object shaped like Phaser's
  // keyboard CursorKeys ({left:{isDown}, right:{isDown}, up:{isDown}}),
  // so the ported update() loop doesn't need to know whether input
  // came from a keyboard or an on-screen d-pad.
  // ---------------------------------------------------------------
  const virtualCursors = {
    left: { isDown: false },
    right: { isDown: false },
    up: { isDown: false },
  };

  function wireTouchButton(elId, key) {
    const el = document.getElementById(elId);
    if (!el) return;
    const press = (e) => { e.preventDefault(); virtualCursors[key].isDown = true; };
    const release = (e) => { e.preventDefault(); virtualCursors[key].isDown = false; };
    el.addEventListener("touchstart", press, { passive: false });
    el.addEventListener("touchend", release, { passive: false });
    el.addEventListener("touchcancel", release, { passive: false });
    el.addEventListener("mousedown", press);
    el.addEventListener("mouseup", release);
    el.addEventListener("mouseleave", release);
  }

  // ---------------------------------------------------------------
  // Scenes — ported from the original js/*.js files
  // ---------------------------------------------------------------
  class BootScene extends Phaser.Scene {
    constructor() { super("BootScene"); }
    create() { this.scene.start("PreloadScene"); }
  }

  class PreloadScene extends Phaser.Scene {
    constructor() { super("PreloadScene"); }
    preload() {
      this.load.image("sky", "game-assets/sky.png");
      this.load.image("ground", "game-assets/platform.png");
      this.load.image("ball", "game-assets/pangball.png");
      this.load.image("net", "game-assets/net.png");
      this.load.spritesheet("dude1", "game-assets/dude1.png", { frameWidth: 32, frameHeight: 48 });
      this.load.spritesheet("dude2", "game-assets/dude2.png", { frameWidth: 32, frameHeight: 48 });
    }
    create() { this.scene.start("GameScene"); }
  }

  class GameScene extends Phaser.Scene {
    constructor() { super("GameScene"); }

    init() {
      this.startGame = false;
      this.gameOver = false;
      this.score = [0, 0];
      this.startRound = false;
      this.playerIndex = -1;
      this.otherPlayerIndex = -1;
      this.maxScore = 5;
    }

    create() {
      var self = this;
      this.net = window.gameNetwork;
      this.otherPlayer = null;

      this.net.on("currentPlayers", function (players) {
        Object.keys(players).forEach(function (id) {
          if (id === self.net.id) {
            if (!self.player) self.addPlayer(self, players[id]);
            self.playerIndex = players[id].index + 1;
            self.otherPlayerIndex = self.playerIndex === 1 ? 2 : 1;
          } else if (!self.otherPlayer) {
            self.addOtherPlayer(self, players[id]);
          }
        });
        if (self.net.tooCrowded && !self.player) {
          self.scoreText.setText("This table's match is already full (2 players)");
        }
      });

      this.net.on("newPlayer", function (playerInfo) {
        if (!self.otherPlayer) self.addOtherPlayer(self, playerInfo);
      });

      this.net.on("disconnect", function () {
        if (self.otherPlayer) {
          self.otherPlayer.destroy();
          self.otherPlayer = null;
          self.startGame = false;
          if (self.scoreText) self.scoreText.setText("Other player left — waiting…");
        }
      });

      this.net.on("playerMoved", function (playerInfo) {
        if (self.otherPlayer) {
          self.otherPlayer.x = playerInfo.x;
          self.otherPlayer.y = playerInfo.y;
        }
      });

      this.net.on("kickedBall", function (playerInfo) {
        if (self.ball) {
          self.ball.x = playerInfo.ballX;
          self.ball.y = playerInfo.ballY;
        }
      });

      this.add.image(400, 300, "sky");

      this.platforms = this.physics.add.staticGroup();
      this.nets = this.physics.add.staticGroup();
      this.platforms.create(400, 568, "ground").setScale(2).refreshBody();
      this.nets.create(12, 394, "net").refreshBody();
      this.nets.create(788, 394, "net").refreshBody();

      this.cursors = this.input.keyboard ? this.input.keyboard.createCursorKeys() : null;

      this.scoreText = this.add.text(16, 16, "Waiting for the other player to scan the table's QR…", {
        fontSize: "22px",
        fill: "#fff",
        wordWrap: { width: 760 },
      });
    }

    update() {
      const touch = virtualCursors;
      const kb = this.cursors;
      const leftDown = (kb && kb.left.isDown) || touch.left.isDown;
      const rightDown = (kb && kb.right.isDown) || touch.right.isDown;
      const upDown = (kb && kb.up.isDown) || touch.up.isDown;

      if (this.player) {
        if (this.startGame) {
          this.addBall(this);
          this.scoreText.setText("Score: " + this.score[0] + " - " + this.score[1]);
        }
        if (this.gameOver) {
          const finalScore = this.score[0] + " - " + this.score[1];
          const iWon = (this.playerIndex === 1 && this.score[0] > this.score[1]) || (this.playerIndex === 2 && this.score[0] < this.score[1]);
          this.scene.start("EndScene", { won: iWon, score: finalScore });
        }
        if (this.startRound) {
          this.ball.x = 400;
          this.ball.y = 16;
          this.ball.setVelocity(0);
          this.player.y = 450;
          this.otherPlayer.y = 450;
          if (this.playerIndex === 1) {
            this.player.x = 100;
            this.otherPlayer.x = 700;
          } else {
            this.player.x = 700;
            this.otherPlayer.x = 100;
          }
          this.startRound = false;
        }

        if (leftDown) {
          this.player.setVelocityX(-160);
          this.player.anims.play("left" + this.playerIndex, true);
        } else if (rightDown) {
          this.player.setVelocityX(160);
          this.player.anims.play("right" + this.playerIndex, true);
        } else {
          this.player.setVelocityX(0);
          this.player.anims.play("turn" + this.playerIndex);
        }

        if (upDown && this.player.body.touching.down) {
          this.player.setVelocityY(-330);
        }

        if (this.otherPlayer) {
          if (this.otherPlayerIndex === 1) this.otherPlayer.anims.play("right1", true);
          else this.otherPlayer.anims.play("left2", true);
        }

        var x = this.player.x;
        var y = this.player.y;
        if (this.player.oldPosition && (x !== this.player.oldPosition.x || y !== this.player.oldPosition.y)) {
          this.net.emit("playerMoved", { x: x, y: y });
        }
        this.player.oldPosition = { x: this.player.x, y: this.player.y };
      }
    }

    addPlayer(self, playerInfo) {
      var spriteIndex = "1";
      var x = 100;
      if (playerInfo.index === 1) { x = 700; spriteIndex = "2"; }
      self.player = self.physics.add.sprite(x, 450, "dude" + spriteIndex);
      self.addPlayerPhysics(self, self.player, spriteIndex);
    }

    addOtherPlayer(self, playerInfo) {
      var spriteIndex = "1";
      var x = 100;
      if (playerInfo.index === 1) { x = 700; spriteIndex = "2"; }
      self.otherPlayer = self.physics.add.sprite(x, 450, "dude" + spriteIndex);
      this.addPlayerPhysics(self, self.otherPlayer, spriteIndex);
      self.otherPlayer.playerId = playerInfo.playerId;
      self.startGame = true;
    }

    addPlayerPhysics(self, player, spriteIndex) {
      player.setScale(PLAYER_SCALE); // bigger, easier to see on a phone screen — about half the goal's height
      player.setBounce(0);
      player.setCollideWorldBounds(true);
      self.physics.add.collider(player, self.platforms);

      if (!this.anims.exists("left" + spriteIndex)) {
        this.anims.create({
          key: "left" + spriteIndex,
          frames: this.anims.generateFrameNumbers("dude" + spriteIndex, { start: 0, end: 3 }),
          frameRate: 10,
          repeat: -1,
        });
        this.anims.create({
          key: "turn" + spriteIndex,
          frames: [{ key: "dude" + spriteIndex, frame: 4 }],
          frameRate: 20,
        });
        this.anims.create({
          key: "right" + spriteIndex,
          frames: this.anims.generateFrameNumbers("dude" + spriteIndex, { start: 5, end: 8 }),
          frameRate: 10,
          repeat: -1,
        });
      }
    }

    addBall(self) {
      self.startGame = false;
      self.balls = self.physics.add.group();
      self.ball = self.balls.create(400, 16, "ball");
      self.ball.setScale(BALL_SCALE); // a little bigger — easier to see and to hit
      self.ball.setBounce(0.6);
      self.ball.setCircle(16);
      self.ball.setFriction(0.005);
      self.ball.setCollideWorldBounds(true);
      self.physics.add.collider(self.ball, self.platforms);
      self.physics.add.collider(self.otherPlayer, self.ball, self.kickBall, null, self);
      self.physics.add.collider(self.player, self.ball, self.kickBall, null, self);
      self.physics.add.collider(self.balls, self.nets, self.scoreGoal, null, self);
    }

    kickBall(player, ball) {
      if (player.x < ball.x) ball.setVelocityX(300);
      else ball.setVelocityX(-300);
      if (player.y < ball.y) ball.setVelocityY(-300);
      else ball.setVelocityY(300);
      this.net.emit("kickedBall", { ballX: ball.x, ballY: ball.y });
    }

    scoreGoal(ball, net) {
      if (ball.y > 110) {
        if (net.x < 400) this.score[1] += 1;
        else this.score[0] += 1;
        this.scoreText.setText("Score: " + this.score[0] + " - " + this.score[1]);
        if (this.score[0] === this.maxScore || this.score[1] === this.maxScore) this.gameOver = true;
        else this.startRound = true;
      }
    }
  }

  class EndScene extends Phaser.Scene {
    constructor() { super("EndScene"); }
    create(data) {
      const cx = this.cameras.main.worldView.x + this.cameras.main.width / 2;
      const cy = this.cameras.main.worldView.y + this.cameras.main.height / 2;
      this.add.text(cx, cy - 60, data.won ? "You won! \u{1F3C6}" : "You lost!", {
        fontSize: "52px",
        fill: data.won ? "#2F5D50" : "#B4482F",
      }).setOrigin(0.5);
      this.add.text(cx, cy, data.score, { fontSize: "44px", fill: "#fff" }).setOrigin(0.5);

      // The on-screen "Play again" button (real HTML, not a canvas tap
      // zone) does the actual restart — this is the same, proven-reliable
      // mechanism the touch controls already use, rather than depending
      // on a canvas-wide pointerdown listener that can be finicky inside
      // an iframe on mobile.
      window.__endScene = this;
      const btn = document.getElementById("btn-play-again");
      if (btn) btn.style.display = "block";
    }
  }

  // ---------------------------------------------------------------
  // Bootstrap
  // ---------------------------------------------------------------
  window.gameNetwork = new RealtimeShim(myId);

  document.getElementById("game-title").textContent = restaurantName ? `${restaurantName} — 2-Player Football` : "2-Player Football";

  const config = {
    type: Phaser.AUTO,
    parent: "phaser-container",
    width: 800,
    height: 600,
    scale: {
      mode: Phaser.Scale.FIT,
      autoCenter: Phaser.Scale.CENTER_BOTH,
    },
    physics: {
      default: "arcade",
      arcade: { gravity: { y: 300 }, debug: false },
    },
    scene: [BootScene, PreloadScene, GameScene, EndScene],
  };

  new Phaser.Game(config);

  wireTouchButton("btn-left", "left");
  wireTouchButton("btn-right", "right");
  wireTouchButton("btn-jump", "up");

  document.getElementById("btn-fullscreen").addEventListener("click", () => {
    const el = document.documentElement;
    if (el.requestFullscreen) el.requestFullscreen();
    else if (el.webkitRequestFullscreen) el.webkitRequestFullscreen();
  });

  document.getElementById("btn-play-again").addEventListener("click", (e) => {
    e.preventDefault();
    if (window.__endScene) {
      window.__endScene.scene.start("GameScene");
      window.__endScene = null;
    }
    document.getElementById("btn-play-again").style.display = "none";
  });
})();
