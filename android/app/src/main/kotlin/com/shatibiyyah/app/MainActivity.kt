package com.shatibiyyah.app

// just_audio_background / audio_service requires the host Activity to extend
// AudioServiceActivity so the background media service binds to the correct FlutterEngine.
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity()
