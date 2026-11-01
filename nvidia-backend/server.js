import app from "./index.js";

const PORT = process.env.PORT || 3000;
const MODEL = "nvidia/nemotron-3.5-lightning-30b-a3b";

app.listen(PORT, "0.0.0.0", () => {
  console.log(`\n🚀 Journii NVIDIA NIM backend running on port ${PORT}`);
  console.log(`🤖 Model: ${MODEL}`);
  console.log(`🌐 Port: ${PORT}`);
});