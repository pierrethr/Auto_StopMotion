// .......................................................................
//
// Substract background from webcam image using RunwayML's YOLACT model
// and saves the resulting image as a .jpg sequence
// SPACE to save first frame
// saving of next frames will happen automatically if camera image is different enough from previously captured one (see snapDiffThreshold parameter)
// M to toggle between Record Mode and Playback Mode
//
// Note: Make sure RunwayML is running before starting this app
//
// .......................................................................


// import video library
import processing.video.*;

import java.util.Date;
import java.io.File;

// import Runway library
import com.runwayml.*;

boolean mode = false; // 0 = record, 1 = play

// reference to runway instance
RunwayHTTP runway;
PImage runwayResult;

// periocally to be updated using millis()
int lastMillis;
// how often should the above be updated and a time action take place ?
int waitTime = 1000;

// reference to the camera
Capture camera;
PImage camImg;
PImage prevCamImg;

// status
String status = "waiting ~"+(waitTime/1000)+"s";

int snapTimerDuration = 4000;
int snapTimerStart;
boolean bTimerOn = false;
boolean isWaitingForRunway = false;
String currentRecFolder = "";

boolean bCompareCams = false;
float snapDiffThreshold = .07;

// *****************************

ArrayList<String> animFolders = new ArrayList<String>();
ArrayList<String> currentAnimFiles = new ArrayList<String>();
int currentAnim = 0;
int currentFrame = 0;

PImage frameImg;
int animFPS = 5;
int frameStartTime;
int frameDuration = round(1000 / animFPS);

// --------------------------------------------------------
void setup(){
  String[] cameras = Capture.list();
  
  // match sketch size to default model camera setup
  size(1200,400);
  // setup Runway
  runway = new RunwayHTTP(this);
  // update manually
  runway.setAutoUpdate(false);
  // setup camera
  camera = new Capture(this,600,400, cameras[0]);
  camera.start();
  // setup timer
  lastMillis = millis();
}

// --------------------------------------------------------
void draw(){
  background(25, 200, 100);

  
  if (!mode) {
    DrawRecordMode();
  } else {
    DrawPlaybackMode();
  }

}

private void DrawPlaybackMode() {
  if (frameImg != null) {
    image(frameImg, 0, 0, 600, 400);

    CheckFrameTimer();
  }
}

// --------------------------------------------------------
private void DrawRecordMode() {
  // update timer
  int currentMillis = millis();
  // if the difference between current millis and last time we checked past the wait time
  if(currentMillis - lastMillis >= waitTime){
    status = "sending image to Runway";
    // call the timed function
    sendFrameToRunway();
    // update lastMillis, preparing for another wait
    lastMillis = currentMillis;
  }

  // draw image received from Runway
  if(runwayResult != null){
    runwayResult.loadPixels();
    
    for (int i = 0; i < runwayResult.pixels.length; i++) {
      if (colorDist(runwayResult.pixels[i], camImg.pixels[i]) < 50) {
        runwayResult.pixels[i] = color(255); // set pixel to white
        camImg.pixels[i] = color(255); 
      }
    }
    
    runwayResult.updatePixels();
    camImg.updatePixels();
    
    image(runwayResult,600,0);

    if (isWaitingForRunway) {
      SnapCamImg();
      isWaitingForRunway = false;
    }
  }
  

  if (camImg != null) image(camImg,0,0,600,400);
  
  fill(0);
  textSize(12);
  text(status,5,15);

  CompareCams();
}

private void CompareCams() {
  float diffRatio = 0;

  if (prevCamImg != null) {
    diffRatio = GetImgDiffRatio();
    
    // image(prevCamImg,600,0,600,400);

    textSize(12);
    text(str(diffRatio), 5, 40);
  }

  if (bCompareCams && diffRatio >= snapDiffThreshold) {
    StartSnapTimer();
  }

  if (bTimerOn) {
    CheckSnapTimer();
    int timeLeft = round(((snapTimerStart + snapTimerDuration) - millis()) / 1000);

    textSize(50);
    text(str(timeLeft), width/2, height/2);
  }
}

// --------------------------------------------------------
private void StartSnapTimer() {
  ToggleCompareCams();

  snapTimerStart = millis();
  bTimerOn = true;
}

// --------------------------------------------------------
private void CheckSnapTimer() {
  if (millis() >= snapTimerStart + snapTimerDuration) {
    // SnapCamImg();
    bTimerOn = false;
    isWaitingForRunway = true;
  }
}

// --------------------------------------------------------
void sendFrameToRunway(){
  // nothing to send if there's no new camera data available
  if(camera.available() == false){
    return;
  }
  // read a new frame
  camera.read();
  // crop image to Runway input format (600x400)
  camImg = camera.get(0,0,600,400);
  camImg.loadPixels();
  // query Runway with webcam image 
  runway.query(camImg,ModelUtils.IMAGE_FORMAT_JPG,"input_image");
}


// --------------------------------------------------------
// this is called when new Runway data is available
void runwayDataEvent(JSONObject runwayData){
  // point the sketch data to the Runway incoming data 
  String base64ImageString = runwayData.getString("output_image");
  // try to decode the image from
  try{
    runwayResult = ModelUtils.fromBase64(base64ImageString);
  }catch(Exception e){
    e.printStackTrace();
  }
  status = "received runway result";
}

// --------------------------------------------------------
// this is called each time Processing connects to Runway
// Runway sends information about the current model
public void runwayInfoEvent(JSONObject info){
  println(info);
}

// --------------------------------------------------------
// if anything goes wrong
public void runwayErrorEvent(String message){
  println(message);
}

float colorDist(color c1, color c2)
{
  float rmean =(red(c1) + red(c2)) / 2;
  float r = red(c1) - red(c2);
  float g = green(c1) - green(c2);
  float b = blue(c1) - blue(c2);
  return sqrt((int(((512+rmean)*r*r))>>8)+(4*g*g)+(int(((767-rmean)*b*b))>>8));
} // colorDist()




// --------------------------------------------------------
private void LoadAnims() {
  println("LoadAnim");
  String path = sketchPath() + "/data/";

  // list folders
  String[] filenames = listFileNames(path);
  printArray(filenames);

  for (int f = 0; f < filenames.length; f++) {
    if (!filenames[f].contains(".") && filenames[f] != ".DS_Store") {
      animFolders.add(filenames[f]);
    }
  }

  NextAnim();
}

// --------------------------------------------------------
private void NextAnim() {
  if (currentAnim + 1 <= animFolders.size()-1) {
    currentAnim++;
  } else {
    currentAnim = 0;
  }

  currentFrame = 0;

  LoadCurrentAnimFiles();
}

// --------------------------------------------------------
private void PrevAnim() {
  if (currentAnim-1 > 0) {
    currentAnim--;
  } else {
    currentAnim = animFolders.size()-1;
  }

  currentFrame = 0;

  LoadCurrentAnimFiles();
}

// --------------------------------------------------------
private void LoadCurrentAnimFiles() {
  currentAnimFiles.clear();
  println("LoadCurrentAnimFiles " + currentAnim + " : " + animFolders.get(currentAnim));

  String path = sketchPath() + "/data/" + animFolders.get(currentAnim);
  String[] filenames = listFileNames(path);
  printArray(filenames);

  for (int f = 0; f < filenames.length; f++) {
    if (filenames[f].contains(".")) {
      currentAnimFiles.add(filenames[f]);
    }
  }

  NextFrame();
}

// --------------------------------------------------------
private void NextFrame() {
  if (currentFrame + 1 < currentAnimFiles.size()-1) {
    currentFrame++;
  } else {
    currentFrame = 0;
  }

  frameStartTime = millis();
  frameImg = loadImage("data/" + animFolders.get(currentAnim) + "/" + currentAnimFiles.get(currentFrame));

}

// --------------------------------------------------------
private void CheckFrameTimer() {
  if (millis() >= frameStartTime + frameDuration) {
    NextFrame();
  }
}

// --------------------------------------------------------
// This function returns all the files in a directory as an array of Strings  
String[] listFileNames(String dir) {
  File file = new File(dir);
  if (file.isDirectory()) {
    String names[] = file.list();
    return names;
  } else {
    // If it's not a directory
    return null;
  }
}

// --------------------------------------------------------
private void SnapCamImg() {
  Date d = new Date();

  if (currentRecFolder == "") {
    currentRecFolder = "data/"+String.valueOf(d.getTime());
    createOutput(currentRecFolder+"/empty");
  }

  camImg.save(currentRecFolder + "/" + String.valueOf(d.getTime()) + ".jpg");

  prevCamImg = camImg.get(0,0,600,400);

  ToggleCompareCams();
}

// --------------------------------------------------------
private float GetImgDiffRatio() {
  int nDiffPixels = 0;

  camImg.loadPixels();
  prevCamImg.loadPixels();

  for (int i = 0; i < 600*400; i++) {
    if (colorDist(camImg.pixels[i], prevCamImg.pixels[i]) > 50) {
      nDiffPixels++;
    }
  }

  return (float)nDiffPixels / (float)camera.pixels.length;
}

// --------------------------------------------------------
private void ToggleCompareCams() { bCompareCams = !bCompareCams; }

// --------------------------------------------------------
void keyPressed() {
  if (key == CODED) {
    if (keyCode == RIGHT) {
      NextAnim();
    } else if (keyCode == LEFT) {
      PrevAnim();
    }
  } else {
    if (key == ' ') {
      SnapCamImg();
    } else if (key == 'm') {
      mode = !mode;

      if (mode) {
        LoadAnims();
      } else {
        currentRecFolder = "";
        bTimerOn = false;
        isWaitingForRunway = false;
      }
    }
  }
  
}


