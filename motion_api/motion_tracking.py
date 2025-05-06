from flask import Flask, Response, jsonify, request
import cv2 as cv
import numpy as np
from ultralytics import YOLO
import threading
import time
import json
import speech_recognition as sr
import pyttsx3
from flask_cors import CORS
import os
import firebase_admin
from firebase_admin import credentials, firestore
import base64

# Initialize Flask app
app = Flask(__name__)
CORS(app)  # Enable CORS for Flutter app

# Configure Firebase Emulator
os.environ["FIRESTORE_EMULATOR_HOST"] = "localhost:8080" 

# Initialize Firebase with emulator
cred = credentials.Certificate(r"./firebase-cardential/")
firebase_admin.initialize_app(cred)
db = firestore.client()

# Global variables
model = YOLO("./yolo11n-pose.pt")  # Use a valid path or download the model
counters = {
    "left_hand": 0,
    "right_hand": 0,
    "combine": 0,
    "left_tricep": 0,
    "right_tricep": 0,
}
mode = "normal"
is_running = False
current_frame = None
angles = {"left": 0, "right": 0}
voice_recognition_active = False
active_users = {}  # Track active users by UID

# Configure thresholds
thresholds = {
    "bicep_up": 170,
    "bicep_down": 45,
    "tricep_up": 170,
    "tricep_down": 90
}

# States
states = {
    "push_up_left": False,
    "push_up_right": False,
    "combine": False,
    "tricep_push_left": False,
    "tricep_push_right": False,
}

# Initialize text-to-speech engine
engine = pyttsx3.init()
voices = engine.getProperty('voices')
engine.setProperty('voice', voices[0].id)
engine.setProperty('rate', 150)

def speak(text):
    if voice_recognition_active:
        engine.say(text)
        engine.runAndWait()

def calculate_angle(a, b, c):
    a = np.array(a)
    b = np.array(b)
    c = np.array(c)
    
    radians = np.arctan2(c[1]-b[1], c[0]-b[0]) - np.arctan2(a[1]-b[1], a[0]-b[0])
    angle = np.abs(radians*180.0/np.pi)
    
    if angle > 180.0:
        angle = 360-angle
    return angle

def process_frame(frame):
    global angles, counters, mode, states
    
    frame = cv.resize(frame, (720, 480))
    result = model.track(frame)
    
    if result[0].keypoints is not None:
        keypoints = result[0].keypoints.xy.cpu().numpy()
        
        for keypoint in keypoints:
            if len(keypoint) > 0:
                if len(keypoint) > 10:  # We need at least 11 points
                    # Extract joint positions
                    left_shoulder = (int(keypoint[5][0]), int(keypoint[5][1]))
                    left_elbow = (int(keypoint[7][0]), int(keypoint[7][1]))
                    left_wrist = (int(keypoint[9][0]), int(keypoint[9][1]))
                    
                    right_shoulder = (int(keypoint[6][0]), int(keypoint[6][1]))
                    right_elbow = (int(keypoint[8][0]), int(keypoint[8][1]))
                    right_wrist = (int(keypoint[10][0]), int(keypoint[10][1]))
                    
                    # Calculate angles
                    left_hand_angle = calculate_angle(left_shoulder, left_elbow, left_wrist)
                    right_hand_angle = calculate_angle(right_shoulder, right_elbow, right_wrist)
                    
                    angles["left"] = int(left_hand_angle)
                    angles["right"] = int(right_hand_angle)
                    
                    # Process based on mode
                    if mode == "normal":
                        # Bicep curls - Left
                        if left_hand_angle < thresholds["bicep_down"] and not states["push_up_left"]:
                            states["push_up_left"] = True
                            counters["left_hand"] += 1
                            speak(f"left {counters['left_hand']}")
                        elif left_hand_angle > thresholds["bicep_up"] and states["push_up_left"]:
                            states["push_up_left"] = False
                        
                        # Bicep curls - Right
                        if right_hand_angle < thresholds["bicep_down"] and not states["push_up_right"]:
                            states["push_up_right"] = True
                            counters["right_hand"] += 1
                            speak(f"right {counters['right_hand']}")
                        elif right_hand_angle > thresholds["bicep_up"] and states["push_up_right"]:
                            states["push_up_right"] = False
                            
                    elif mode == "combine":
                        # Combined bicep curls
                        if (right_hand_angle <= thresholds["bicep_down"] and 
                            left_hand_angle <= thresholds["bicep_down"] and not states["combine"]):
                            states["combine"] = True
                            counters["combine"] += 1
                            speak(f"combine {counters['combine']}")
                        elif (left_hand_angle >= thresholds["bicep_up"] and 
                              right_hand_angle >= thresholds["bicep_up"] and states["combine"]):
                            states["combine"] = False
                            
                    elif mode == "triceps":
                        # Tricep extensions - Left
                        if left_hand_angle > thresholds["tricep_up"] and not states["tricep_push_left"]:
                            states["tricep_push_left"] = True
                            counters["left_tricep"] += 1
                            speak(f"left tricep {counters['left_tricep']}")
                        elif left_hand_angle < thresholds["tricep_down"] and states["tricep_push_left"]:
                            states["tricep_push_left"] = False
                        
                        # Tricep extensions - Right
                        if right_hand_angle > thresholds["tricep_up"] and not states["tricep_push_right"]:
                            states["tricep_push_right"] = True
                            counters["right_tricep"] += 1
                            speak(f"right tricep {counters['right_tricep']}")
                        elif right_hand_angle < thresholds["tricep_down"] and states["tricep_push_right"]:
                            states["tricep_push_right"] = False
            
                # Draw keypoints on the frame
                for i, point in enumerate(keypoint):
                    cx, cy = int(point[0]), int(point[1])
                    cv.circle(frame, (cx, cy), 5, (255, 0, 0), -1)
                    cv.putText(frame, f'{i}', (cx, cy), cv.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 255), 1)
                
    # Add text to frame
    cv.putText(frame, f"Mode: {mode}", (10, 30), cv.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 255), 2)
    
    if mode == "normal":
        cv.putText(frame, f"Left: {counters['left_hand']} Right: {counters['right_hand']}", 
                   (10, 60), cv.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 255), 2)
    elif mode == "combine":
        cv.putText(frame, f"Combined: {counters['combine']}", 
                   (10, 60), cv.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 255), 2)
    elif mode == "triceps":
        cv.putText(frame, f"Left Tricep: {counters['left_tricep']} Right Tricep: {counters['right_tricep']}", 
                   (10, 60), cv.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 255), 2)
                   
    # Store current frame for debugging
    global current_frame
    current_frame = frame
    
    return frame

# Voice recognition thread
def voice_recognition_thread():
    global mode, voice_recognition_active
    
    r = sr.Recognizer()
    mic = sr.Microphone()
    
    with mic as source:
        r.adjust_for_ambient_noise(source)
    
    while voice_recognition_active:
        try:
            with mic as source:
                audio = r.listen(source, timeout=5)
                
            # Recognize speech using Google Speech Recognition
            text = r.recognize_google(audio).lower()
            print(f"Recognized: {text}")
            
            # Process commands
            if "normal" in text:
                mode = "normal"
                speak("Normal mode activated")
            elif "combine" in text or "combined" in text:
                mode = "combine"
                speak("Combined mode activated")
            elif "tricep" in text:
                mode = "triceps"
                speak("Tricep mode activated")
            elif "stop" in text:
                is_running = False
                voice_recognition_active = False
                speak("Stopping exercise tracking")
                
        except sr.UnknownValueError:
            pass
        except sr.RequestError:
            print("Could not request results from Google Speech Recognition")
        except Exception as e:
            print(f"Error in voice recognition: {e}")

# API endpoints for Flutter app
@app.route('/start_tracking', methods=['POST'])
def start_tracking():
    global is_running, counters, mode, voice_recognition_active
    
    data = request.get_json()
    uid = data.get('uid')
    selected_mode = data.get('mode', 'normal')
    use_voice = data.get('use_voice', False)
    
    # Reset counters
    counters = {
        "left_hand": 0,
        "right_hand": 0,
        "combine": 0,
        "left_tricep": 0,
        "right_tricep": 0,
    }
    
    mode = selected_mode
    is_running = True
    voice_recognition_active = use_voice
    
    # Save to Firestore Emulator
    if uid:
        workout_ref = db.collection('usersData').document(uid).collection('workouts').document()
        workout_ref.set({
            'start_time': firestore.SERVER_TIMESTAMP,
            'mode': mode,
            'status': 'in_progress'
        })
    
    # Track this user session
    active_users[uid] = {
        'start_time': time.time(),
        'mode': mode,
        'counters': counters.copy(),
        'workout_id': workout_ref.id if uid else None
    }
    
    # Start voice recognition if requested
    if use_voice:
        threading.Thread(target=voice_recognition_thread).start()
    
    return jsonify({'status': 'success', 'message': 'Tracking started'})

@app.route('/stop_tracking', methods=['POST'])
def stop_tracking():
    global is_running, voice_recognition_active
    
    data = request.get_json()
    uid = data.get('uid')
    
    is_running = False
    voice_recognition_active = False
    
    # Store final counters for this user
    if uid in active_users:
        active_users[uid]['end_time'] = time.time()
        active_users[uid]['duration'] = active_users[uid]['end_time'] - active_users[uid]['start_time']
        active_users[uid]['final_counters'] = counters.copy()
        
        # Update Firestore with final results
        if active_users[uid].get('workout_id'):
            workout_ref = db.collection('usersData').document(uid).collection('workouts').document(active_users[uid]['workout_id'])
            workout_ref.update({
                'end_time': firestore.SERVER_TIMESTAMP,
                'status': 'completed',
                'stats': {
                    'left_count': counters['left_hand'],
                    'right_count': counters['right_hand'],
                    'combined_count': counters['combine'],
                    'left_tricep_count': counters['left_tricep'],
                    'right_tricep_count': counters['right_tricep'],
                    'duration': firestore.Increment(active_users[uid]['duration'])
                }
            })
    
    return jsonify({'status': 'success', 'message': 'Tracking stopped'})

@app.route('/change_mode', methods=['POST'])
def change_mode():
    global mode
    
    data = request.get_json()
    new_mode = data.get('mode')
    uid = data.get('uid')
    
    if new_mode in ['normal', 'combine', 'triceps']:
        mode = new_mode
        
        # Update workout mode in Firestore if available
        if uid in active_users and active_users[uid].get('workout_id'):
            workout_ref = db.collection('usersData').document(uid).collection('workouts').document(active_users[uid]['workout_id'])
            workout_ref.update({
                'mode': mode
            })
            
        return jsonify({'status': 'success', 'message': f'Mode changed to {mode}'})
    else:
        return jsonify({'status': 'error', 'message': 'Invalid mode'})

@app.route('/tracking_status', methods=['GET'])
def tracking_status():
    return jsonify({
        'is_running': is_running,
        'mode': mode,
        'counters': counters,
        'angles': angles
    })

@app.route('/toggle_voice', methods=['POST'])
def toggle_voice():
    global voice_recognition_active
    
    data = request.get_json()
    enable = data.get('enable', False)
    
    if enable and not voice_recognition_active:
        voice_recognition_active = True
        threading.Thread(target=voice_recognition_thread).start()
    elif not enable:
        voice_recognition_active = False
    
    return jsonify({
        'status': 'success',
        'voice_active': voice_recognition_active
    })

@app.route('/user_workouts', methods=['GET'])
def user_workouts():
    uid = request.args.get('uid')
    
    if not uid:
        return jsonify({'status': 'error', 'message': 'User ID required'})
    
    try:
        workouts = []
        workouts_ref = db.collection('usersData').document(uid).collection('workouts').order_by('start_time', direction=firestore.Query.DESCENDING).limit(10)
        docs = workouts_ref.stream()
        
        for doc in docs:
            workout_data = doc.to_dict()
            workout_data['id'] = doc.id
            
            # Convert timestamps to strings for JSON
            if 'start_time' in workout_data and workout_data['start_time']:
                workout_data['start_time'] = workout_data['start_time'].strftime('%Y-%m-%d %H:%M:%S')
            if 'end_time' in workout_data and workout_data['end_time']:
                workout_data['end_time'] = workout_data['end_time'].strftime('%Y-%m-%d %H:%M:%S')
                
            workouts.append(workout_data)
            
        return jsonify({'status': 'success', 'workouts': workouts})
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)})

# NEW: Process frames from mobile camera
@app.route('/process_frame', methods=['POST'])
def mobile_frame_processing():
    global is_running
    
    if not is_running:
        return jsonify({'status': 'error', 'message': 'Tracking not started'})
    
    try:
        data = request.get_json()
        base64_image = data.get('image')
        
        if not base64_image:
            return jsonify({'status': 'error', 'message': 'No image data provided'})
        
        # Decode base64 image
        image_data = base64.b64decode(base64_image.split(',')[1] if ',' in base64_image else base64_image)
        nparr = np.frombuffer(image_data, np.uint8)
        frame = cv.imdecode(nparr, cv.IMREAD_COLOR)
        
        if frame is None:
            return jsonify({'status': 'error', 'message': 'Invalid image data'})
        
        # Process the frame
        process_frame(frame)
        
        # Return current counters and status
        return jsonify({
            'status': 'success',
            'counters': counters,
            'angles': angles,
            'mode': mode
        })
        
    except Exception as e:
        print(f"Error processing frame: {e}")
        return jsonify({'status': 'error', 'message': str(e)})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5050, debug=True)
