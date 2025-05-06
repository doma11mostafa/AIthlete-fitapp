<<<<<<< HEAD
# first_project

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
=======
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

AIthlete-fitapp/
├── frontend/         ← flutter app
├── backend/          ← Flask APIs
│   ├── chat_api/
│   └── motio_api/
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

>>>>>>> ebf1acc64dc8ce16da84e21863663c62d334acc4
