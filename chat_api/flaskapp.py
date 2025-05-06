from flask import Flask, request, jsonify
import torch
from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig, pipeline
import firebase_admin
from firebase_admin import credentials, firestore
import uuid
import re
from flask_cors import CORS
import time
import os
import random
from firebase_admin import credentials, firestore
app = Flask(__name__)
CORS(app) 



os.environ["FIRESTORE_EMULATOR_HOST"] = "localhost:8080"

cred = credentials.Certificate('./firebase-cardential/')
firebase_admin.initialize_app(cred)
db = firestore.client()
# model downloading
print("جاري تحميل الموديل...")
model_path = r"Final-project\Chatbot\full_model"  

quantization_config = BitsAndBytesConfig(
    load_in_4bit=True,
    bnb_4bit_compute_dtype=torch.float16,
    bnb_4bit_quant_type="nf4"
)

try:
    model = AutoModelForCausalLM.from_pretrained(
        model_path,
        quantization_config=quantization_config,
        device_map="auto"
    )
    tokenizer = AutoTokenizer.from_pretrained(model_path)
    generator = pipeline("text-generation", model=model, tokenizer=tokenizer)
    print("✅ تم تحميل الموديل بنجاح")
except Exception as e:
    print(f"❌ خطأ أثناء تحميل الموديل: {str(e)}")
    generator = None


GREETING_PATTERNS = [
    r'\b(hi|hello|hey|hola|howdy|greetings)\b',
    r'\bhow are you\b',
    r'\bاهلا|مرحبا|السلام عليكم|هاي|هلو\b'
]

GREETING_RESPONSES = [
    "Hello! I'm AIthlete, your fitness assistant. How can I help you today?",
    "Hi there! I'm AIthlete, your personal fitness advisor. What would you like to know about fitness and training?",
    "Hey! I'm AIthlete, still in preview but ready to assist with your fitness questions! 🏋️‍♂️",
    "Greetings! I'm AIthlete, your fitness companion. I'm here to provide advice on workouts, nutrition, and overall wellness. How can I assist you today? 💪"
]


def is_greeting(message):
    return any(re.search(pattern, message, re.IGNORECASE) for pattern in GREETING_PATTERNS)

def get_greeting_response():
    return random.choice(GREETING_RESPONSES)

def clean_model_response(original_message, response):
    if response.startswith(original_message):
        response = response[len(original_message):].strip()
    return response

def log_to_firebase(user_id, message, response, conversation_id):
    try:
        user_ref = db.collection('users').document(user_id)
        if not user_ref.get().exists:
            user_ref.set({
                'created_at': firestore.SERVER_TIMESTAMP,
                'last_active': firestore.SERVER_TIMESTAMP
            })
        else:
            user_ref.update({'last_active': firestore.SERVER_TIMESTAMP})
        
        conversation_ref = db.collection('conversations').document(conversation_id)
        conversation_ref.set({
            'user_id': user_id,
            'updated_at': firestore.SERVER_TIMESTAMP
        }, merge=True)
        
        messages_ref = conversation_ref.collection('messages')
        messages_ref.add({
            'content': message,
            'sender': 'user',
            'timestamp': firestore.SERVER_TIMESTAMP
        })
        messages_ref.add({
            'content': response,
            'sender': 'assistant',
            'timestamp': firestore.SERVER_TIMESTAMP
        })
        
        return True
    except Exception as e:
        print(f"خطأ في تسجيل المحادثة: {str(e)}")
        return False

# API الرئيسي
@app.route('/api/chat', methods=['POST'])
def chat():
    data = request.json
    user_id = data.get('user_id')
    message = data.get('message')
    conversation_id = data.get('conversation_id', str(uuid.uuid4()))

    if not user_id or not message:
        return jsonify({"error": "user_id و message مطلوبين"}), 400
    
    # if len(message) > 500:
    #     return jsonify({"error": "رسالتك طويلة جدًا. أقصى طول مسموح به هو 500 حرف."}), 400

    start_time = time.time()

    try:
        if is_greeting(message):
            response = get_greeting_response()
        elif generator:
            outputs = generator(
                message,
                max_length=200,
                temperature=0.7,
                top_p=0.9,
                repetition_penalty=1.1
            )
            response = clean_model_response(message, outputs[0]['generated_text'])
        else:
            response = "I'm sorry, the AI model is currently unavailable. Please try again later."

        log_to_firebase(user_id, message, response, conversation_id)

        end_time = time.time()
        response_time = end_time - start_time

        return jsonify({
            "response": response,
            "conversation_id": conversation_id,
            "response_time": response_time
        })

    except Exception as e:
        print(f"خطأ عام: {str(e)}")
        return jsonify({
            "error": "حدث خطأ أثناء معالجة طلبك",
            "details": str(e)
        }), 500

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=4040)
