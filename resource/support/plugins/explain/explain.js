"use strict";


let ExplainPlugin = (function () {

  // GUI elements
  let recordButton, playButton, stopButton, nextButton, prevButton;
  let panel, video, playbackRate;

  // recording stuff
  let blobs;
  let rec;
  let stream;
  let voiceStream;
  let desktopStream;
  let recording = false;

  // playback stuff
  let explainVideoUrl, explainTimes;

  function deckUrlBase() {
    let path = location.pathname;
    return path.substring(0, path.lastIndexOf("-"));
  }

  function deckVideoUrl() {
    return deckUrlBase() + "-recording.mp4";
  }

  function deckTimesUrl() {
    return deckUrlBase() + "-times.json";
  }

  function videoFilenameBase() {
    const pathname = window.location.pathname;
    let filename = pathname.substring(pathname.lastIndexOf('/') + 1);
    filename = filename.substring(0, filename.lastIndexOf("-"));
    return filename;
  }

  function videoFilename() {
    return videoFilenameBase() + '.mp4';
  }


  function currentSlide() {
    let time = video.currentTime();
    let slide = 0;
    while (slide < explainTimes.length && time > explainTimes[slide])
      slide += 1;
    return slide - 1;
  }


  function next() {
    let slide = currentSlide() + 1;
    if (explainTimes[slide]) video.currentTime(explainTimes[slide]);
  }


  function prev() {
    let slide = currentSlide() - 1;
    if (explainTimes[slide]) video.currentTime(explainTimes[slide]);
  }


  function stop() {
    panel.removeAttribute("data-visible");
    video.pause();
    let slide = currentSlide();
    Reveal.slide(slide);
  }


  function play() {
    panel.setAttribute("data-visible", 1);

    let ended = () => {
      // video.off("ended", ended);
      stop();
    };

    let time = video.currentTime();
    let slide = Reveal.getState().indexh;
    if (currentSlide(time) != slide) {
      if (explainTimes[slide])
        video.currentTime(explainTimes[slide]);
      else
        video.currentTime(0);
    }

    video.on("ended", ended);
    video.play();
    video.focus();
  }


  function record() {
    if (!recording) {
      startRecording();
      recording = true;
    }
    else {
      stopRecording();
      recording = false;
    }
  }

  class Timing {
    constructor() {
      this.times = {}
    }

    start(index, slide) {
      this.startTime = Date.now();
      this.record(index, slide);
    }

    record(index, slide) {
      let time = String((Date.now() - this.startTime) / 1000);
      if (!slide.firstShown) {
        console.log("[] " + time + " " + index + ", " + slide.id);
        slide.firstShown = time;
        this.times[time] = {
          slideIndex: index,
          slideId: slide.id
        };
      } else {
        console.log("[] ignored " + index + ", " + slide.id);
      }
    }

    finish() {
      return new Blob([JSON.stringify(this.times, null, 4)], {type: "application/json"});
    }
  }


  async function setupRecording() {

    // get display stream
    console.log('get display stream');
    desktopStream = await navigator.mediaDevices.getDisplayMedia({
      video: {
        frameRate: 30,
        width: 1280,
        height: 720,
        cursor: 'always',
        resizeMode: 'crop-and-scale'
      },
      audio: true
    });

    // get microphone stream
    console.log('get voice stream');
    voiceStream = await navigator.mediaDevices.getUserMedia({
      video: false,
      audio: {
        echoCancellation: true,
        noiseSuppression: true
      }
    });

    // merge tracks into recording stream
    const tracks = [
      ...desktopStream.getVideoTracks(),
      ...mergeAudioStreams(desktopStream, voiceStream)
    ];
    stream = new MediaStream(tracks);

    // show record button
    recordButton.style.display = 'block';
  }

  function download(blob, name) {
    let url = URL.createObjectURL(blob);
    let anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = name;

    document.body.appendChild(anchor);
    anchor.click();
    document.body.removeChild(anchor);
  }

  function startRecording() {
    recordButton.title = "Stop video recording";
    recordButton.classList.remove("fa-circle");
    recordButton.classList.add("fa-stop");

    // clear blobs array
    blobs = [];

    // setup recorder
    rec = new MediaRecorder(stream, {mimeType: 'video/webm; codecs=h264"'});

    rec.ondataavailable = (e) => blobs.push(e.data);

    rec.onstart = () => {
      console.log("[] recorder started")
      rec.timing = new Timing();
      rec.timing.start(0, Reveal.getSlides()[0]);
      Reveal.slide(0);
      Reveal.addEventListener('slidechanged',
        e => rec.timing.record(e.indexh, e.currentSlide));
    };

    rec.onstop = async () => {
      console.log("[] recorder stopped")
      let vblob = new Blob(blobs, {type: 'video/webm'});
      let tblob = rec.timing.finish();

      if (
        !await guardedUploadBlob(deckTimesUrl(), tblob) ||
        !await uploadBlob(deckUrlBase() + "-recording.webm", vblob)
      ) {
        download(vblob, videoFilenameBase() + '-recording.webm');
        download(tblob, videoFilenameBase() + '-times.json');
      }

      stream = null;
      rec = null;
    };

    rec.start();
  }


  function stopRecording() {
    recordButton.title = "Start video recording";
    recordButton.classList.remove("fa-stop");
    recordButton.classList.add("fa-circle");

    rec.stop();
    stream.getTracks().forEach(s => s.stop())
  }


  const mergeAudioStreams = (desktopStream, voiceStream) => {
    const context = new AudioContext();
    const destination = context.createMediaStreamDestination();
    let hasDesktop = false;
    let hasVoice = false;
    if (desktopStream && desktopStream.getAudioTracks().length > 0) {
      const source1 = context.createMediaStreamSource(desktopStream);
      const desktopGain = context.createGain();
      desktopGain.gain.value = 0.7;
      source1.connect(desktopGain).connect(destination);
      hasDesktop = true;
      console.log("recording desktop audio");
    }

    if (voiceStream && voiceStream.getAudioTracks().length > 0) {
      const source2 = context.createMediaStreamSource(voiceStream);
      const voiceGain = context.createGain();
      voiceGain.gain.value = 1.0;
      source2.connect(voiceGain).connect(destination);
      hasVoice = true;
      console.log("recording mic audio");
    }

    return (hasDesktop || hasVoice) ? destination.stream.getAudioTracks() : [];
  };



  function printTimeStamps() {
    for (let i = 0; i < explainTimes.length; i++) {
      let t = explainTimes[i];
      let h = Math.floor(t / 60 / 60);
      let m = Math.floor(t / 60) - (h * 60);
      let s = t % 60;
      let formatted = h.toString().padStart(2, '0') + ':' + m.toString().padStart(2, '0') + ':' + s.toString().padStart(2, '0');
      console.log("slide " + (i + 1) + ": time " + formatted + " = " + t + "s");
    }
    console.log(explainTimes);
  }

  async function resourceExists(url) {
    return fetch(url, {method: "HEAD"})
      .then(r => {
        return r.ok;
      })
      .catch(_ => {
        return false;
      });
  }

  async function fetchResourceJSON(url) {
    return fetch(url)
      .then(r => {
        return r.json();
      })
      .catch(e => {
        console.log("[] cannot fetch: " + url + ", " + e);
        return null;
      });
  }

  async function uploadBlob(url, blob) {
    return fetch(url, {method: "PUT", body: blob})
      .then(r => {
        return r.ok;
      })
      .catch(e => {
        console.log("[] cannot upload " + blob.size + " bytes to: " + url + ", " + e);
        return false;
      })
  }

  async function guardedUploadBlob(url, blob) {
    if (await resourceExists(url) && !confirm("Really overwrite existing recording?"))
      return false;
    else
      return uploadBlob(url, blob);
  }

  // setup key binding
  Reveal.addKeyBinding({keyCode: 82, key: 'R', description: 'Setup Recording'}, setupRecording);


  return {
    init: async function () {

      // get config
      let config = Reveal.getConfig().explain;
      if (config) {
        if (config.video) {
          explainVideoUrl = config.video;
          if (explainVideoUrl.endsWith("/")) {
            explainVideoUrl += videoFilename();
          }
        }
        explainTimes = config.times ? JSON.parse(config.times) : [0];
        console.log("[] explanation source configured");
      } else if (await resourceExists(deckVideoUrl()) && await resourceExists(deckTimesUrl())) {
        explainVideoUrl = deckVideoUrl();
        let deckTimes = await fetchResourceJSON(deckTimesUrl());
        explainTimes = Object.keys(deckTimes);
        console.log("[] explanation source implicit");
      } else {
        console.log("[] no explanation source");
      }

      recordButton = document.createElement("button");
      recordButton.id = "dvo-record";
      recordButton.classList.add("dvo-button", "fas", "fa-circle");
      recordButton.title = "Start video recording";
      recordButton.addEventListener("click", record);
      document.body.appendChild(recordButton);
      recordButton.style.display = 'none';

      playButton = document.createElement("button");
      playButton.id = "dvo-play";
      playButton.classList.add("dvo-button", "fas", "fa-play");
      playButton.addEventListener("click", play);
      playButton.title = "Play video recording";
      document.body.appendChild(playButton);

      panel = document.createElement("div");
      panel.id = "dvo-panel";
      document.body.appendChild(panel);

      // prevButton = document.createElement("button");
      // prevButton.id = "dvo-prev";
      // prevButton.classList.add("dvo-button", "fas", "fa-step-backward");
      // prevButton.addEventListener("click", prev);
      // prevButton.title = "Jump to previous slide";

      // nextButton = document.createElement("button");
      // nextButton.id = "dvo-next";
      // nextButton.classList.add("dvo-button", "fas", "fa-step-forward");
      // nextButton.addEventListener("click", next);
      // nextButton.title = "Jump to next slide";

      // stopButton = document.createElement("button");
      // stopButton.id = "dvo-stop";
      // stopButton.classList.add("dvo-button", "fas", "fa-stop");
      // stopButton.addEventListener("click", stop);
      // stopButton.title = "Stop video";

      // let controls = document.createElement('div');
      // controls.id = 'dvo-controls';
      // controls.appendChild(prevButton);
      // controls.appendChild(nextButton);
      // controls.appendChild(stopButton);
      // panel.appendChild(controls);

      let v = document.createElement("video");
      v.id = 'dvo-video';
      v.classList.add('video-js');
      panel.appendChild(v);

      // setup video-js
      video = videojs('dvo-video', {
        width: "100%",
        height: "100%",
        controls: true,
        autoplay: false,
        preload: 'metadata',
        playbackRates: [0.5, 0.75, 1, 1.25, 1.5, 2],
        controlBar: {
          playToggle: true,
          volumePanel: true,
          currentTimeDisplay: true,
          timeDivider: false,
          durationDisplay: false,
          remainingTimeDisplay: true,
          playbackRateMenuButton: true,
          fullscreenToggle: false,
          pictureInPictureToggle: false
        },
        userActions: {
          hotkeys: function(event) {
            event.stopPropagation();

            // `this` is the player in this context

            switch (event.code)
            {
              // space: play/pause
              case 'Space':
                if (this.paused())
                  this.play();
                else
                  this.pause();
                break;

              // left/right: skip slides
              case 'ArrowLeft':
                prev();
                break;
              case 'ArrowRight':
                next();
                break;

              // esc: stop and hide video
              case 'Escape':
                stop();
                break;

              // t: record time stamp, print to console
              case 'KeyT':
                explainTimes.push(Math.floor(video.currentTime()));
                printTimeStamps();
                break;
            }
          }
        }
      });

      video.on('error', _ => {
        console.error("ExplainPlugin: Could not open video \"" + explainVideoUrl + "\"");
        playButton.style.visibility = 'hidden';
      });


      // add custom buttons to videojs control bar
      let stopButton = video.controlBar.addChild("button", {}, 0);
      stopButton.addClass("vjs-icon-cancel");
      stopButton.el().onclick = stop;
      stopButton.el().title = "Stop video, back to slide";

      let prevButton = video.controlBar.addChild("button", {}, 1);
      prevButton.addClass("vjs-icon-previous-item");
      prevButton.el().onclick = prev;
      prevButton.el().title = "Skip to previous slide";

      let nextButton = video.controlBar.addChild("button", {}, 3);
      nextButton.addClass("vjs-icon-next-item");
      nextButton.el().onclick = next;
      nextButton.el().title = "Skip to next slide";


      // if we have a video, use it
      if (explainVideoUrl && explainTimes) {
        recordButton.style.display = 'none';
        video.src({type: 'video/mp4', src: explainVideoUrl});
      }
      // otherwise let's record one
      else {
        playButton.style.display = 'none';
      }
    }
  };

})();

Reveal.registerPlugin('explain', ExplainPlugin);
