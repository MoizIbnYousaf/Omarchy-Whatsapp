import QtQuick
import QtTest
import MediaFixtures
import "../plugins/omawhatsapp" as Oma
TestCase {
 id: suite; name: "SafeAnimation"; when: windowShown; visible:true; width:200;height:200
 Component { id: animation; Oma.SafeAnimatedImage { width:100;height:100 } }
 function test_frames_data(){return [{tag:"gif",file:"multi.gif"},{tag:"webp",file:"multi.webp"}]}
 function test_frames(data){
  var a=createTemporaryObject(animation,suite,{source:MediaFixtures.url(data.file)})
  tryCompare(a,"status",Image.Ready)
  verify(a.frameCount>1)
  tryVerify(function(){return a.currentFrame>0},2500)
  a.playing=false
  var stopped=a.currentFrame;wait(350);compare(a.currentFrame,stopped)
  a.playing=true
  tryVerify(function(){return a.currentFrame!==stopped},2500)
  a.source=MediaFixtures.url("broken.gif")
  tryCompare(a,"status",Image.Error)
  wait(100);compare(a.status,Image.Error)
  a.source=MediaFixtures.url(data.file)
  tryCompare(a,"status",Image.Ready)
 }
 function test_repeated_loading_stopped_posters(){
  for(var i=0;i<30;i++){
   var a=createTemporaryObject(animation,suite,{playing:false,source:MediaFixtures.url("multi.gif")})
   tryCompare(a,"status",Image.Ready)
   compare(a.currentFrame,0);a.destroy();wait(0)
  }
 }
 function test_quickshell_local_asset_url(){
  var path=MediaFixtures.url("multi.gif").toString().replace("file:","qs:")
  var a=createTemporaryObject(animation,suite,{source:path})
  tryCompare(a,"status",Image.Ready)
  verify(a.frameCount>1)
 }
 function test_reentrant_source_change(){
  var a=createTemporaryObject(animation,suite)
  a.sourceSizeChanged.connect(function(){if(a.sourceSize.width>0)a.source=""})
  a.source=MediaFixtures.url("multi.gif")
  wait(100);compare(a.status,Image.Null)
 }
 function test_failed_and_replaced_sources(){
  var a=createTemporaryObject(animation,suite)
  a.source=MediaFixtures.url("multi.gif")
  a.source=MediaFixtures.url("multi.webp")
  a.source="";wait(20);compare(a.status,Image.Null)
  a.source="https://example.invalid/private.gif";tryCompare(a,"status",Image.Error)
 }
}
