import QtQuick
import QtMultimedia
import QtTest
import MediaFixtures
import "../plugins/omawhatsapp" as Oma
TestCase {
 id: suite; name: "MediaBoundary"; when: windowShown; visible:true; width:400;height:400
 Component { id: image; Oma.SafeImage { width:100;height:100 } }
 Component { id: player; Oma.SafeMediaPlayer { kind:"video"; audioOutput: AudioOutput { muted:true } } }

 function test_png_metadata_bomb_renders_pixels(){
  var a=createTemporaryObject(image,suite,{source:MediaFixtures.url("metadata-bomb.png")})
  tryCompare(a,"status",Image.Ready,10000)
  compare(a.sourceSize.width,1);compare(a.sourceSize.height,1)
 }
 function test_first_frame_survives_hidden_load(){
  var a=createTemporaryObject(image,suite,{visible:false,source:MediaFixtures.url("metadata-bomb.png")})
  tryCompare(a,"status",Image.Ready,10000)
  a.visible=true;wait(100)
  var pixels=grabImage(a)
  compare(pixels.pixel(50,50),"#112233")
 }
 function test_static_failure_and_recovery(){
  var a=createTemporaryObject(image,suite,{source:MediaFixtures.url("broken.gif")})
  tryCompare(a,"status",Image.Error)
  a.source=MediaFixtures.url("metadata-bomb.png")
  tryCompare(a,"status",Image.Ready)
  a.source="https://example.invalid/photo.png";tryCompare(a,"status",Image.Error)
 }
 function test_concurrent_images_and_cancellation(){
  var list=[]
  for(var i=0;i<24;i++)list.push(createTemporaryObject(image,suite,{source:MediaFixtures.url("metadata-bomb.png")}))
  list[0].source=""
  for(i=1;i<list.length;i++)tryCompare(list[i],"status",Image.Ready,10000)
  compare(list[0].status,Image.Null)
 }
 function test_regenerated_video_plays(){
  var p=createTemporaryObject(player,suite,{source:MediaFixtures.url("synthetic.mp4")})
  p.play()
  tryVerify(function(){return p.duration>0 || p.error!==MediaPlayer.NoError},15000)
  compare(p.errorString, "")
  verify(p.duration>0)
  compare(p.error,MediaPlayer.NoError)
  tryVerify(function(){return p.position>0},5000)
  p.pause();var pos=p.position;wait(150);verify(Math.abs(p.position-pos)<100)
  p.source=MediaFixtures.url("broken.gif")
  tryCompare(p,"mediaStatus",MediaPlayer.InvalidMedia,10000)
  p.source="";p.stop()
 }
}
