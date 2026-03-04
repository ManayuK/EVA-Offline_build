This is an extension of the original EVA repository(https://github.com/ManayuK/EVA) rebuilt to be completely free from any backend dependency. 
EVA is a fully offline, AI-powered menstrual health and wellness tracking app built with Flutter. 
It uses on-device machine learning — including a Kalman filter, XGBoost-style prediction, 
and a local LLM via llama.cpp to give personalised cycle predictions, journal analysis, and health insights, all without sending any data to a server.

Features
Cycle Tracking

Log period start dates and flow intensity
XGBoost + Kalman filter blend for next cycle prediction
Ovulation window and fertile period estimation
PMS risk scoring with feedback loop
Cycle history with length trend chart
Phase-based calendar (Menstrual / Follicular / Ovulation / Luteal)

AI Insights

Personalised suggestions based on current phase, mood, sleep, goals, and diet
Health risk indicators (cycle irregularity, mood patterns, sleep deficits)
AI-generated daily phase tips (cached per day)
Emotion timeline and mood heatmap charts
Phase task recommendations
Symptom correlation analysis

Journal

Free-text journaling with sentiment analysis
On-device emotion detection (keyword NLP + mental health concern flagging)
Local LLM generates empathetic responses to entries
Past entries viewable, expandable, editable, and deletable
3000-character limit with soft counter

Chat (EVA AI)

Conversational AI powered by a local llama.cpp model (Gemma / Mistral / Phi)
Full chat history with session sidebar
Text-to-speech for AI responses
Context-aware (knows your current phase, recent mood, symptoms)
Works fully offline after one-time model download

Health Tracking

Sleep journal — hours, quality (1–5 stars), bed/wake time picker, dream notes
Weight tracker — weight logs with BMI calculation and trend chart
Sleep stats banner (avg hours, avg quality, monthly count)

Calendar

Monthly view with phase colour coding
Symptom and mood overlays
Tap any day to see phase details

Profile & Settings

Editable name, cycle length (21–45 days), period length (2–10 days)
Onboarding: DOB, height, weight, fitness level, health goals, dietary preference
PDF health report generator (personal + doctor format)
Sleep journal and weight tracker shortcuts
Reset app data (wipes DB + prefs cleanly)
