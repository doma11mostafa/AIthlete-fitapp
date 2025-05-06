# AIthlete-fitapp
AI fitness Companion
# 💪 Fitness AI App

A smart fitness mobile application that includes:
- A Flutter mobile app
- A Flask-based chatbot for diet and workout recommendations
- A motion tracking backend using YOLO
- Integration with Firebase Emulator and Health Connect

---

## 📁 Project Structure

Fitness-AI-App/
├── mobile_app/
├── chatbot_backend/
│ ├── app.py
│ ├── requirements.txt
│ └── model_loader.py
├── motion_tracking_backend/
│ ├── tracking_app.py
│ └── requirements.txt
├── README.md
└── .gitignore


---

## ⚙️ How to Run

### 1. Run Firebase Emulator (from Flutter app folder)

```bash
cd Fitness_App/
firebase emulators:start --only firestore,auth,storage

flutter pub get
flutter run

cd chatbot_backend/
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r requirements.txt
python app.py



from transformers import AutoModelForCausalLM, AutoTokenizer
model = AutoModelForCausalLM.from_pretrained("yourname/fitness-chatbot")


cd motion_tracking_backend/
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python tracking_app.py


🧠 AI Model
The chatbot model is fine-tuned and uploaded to Hugging Face:
View Model on Hugging Face: < https://huggingface.co/domamostafa/Fitness-Assistance >

