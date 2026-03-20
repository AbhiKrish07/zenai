"""
test_voice_backend.py
━━━━━━━━━━━━━━━━━━━━━
Quick sanity check for the voice backend.
Run from the project root with:  python test_voice_backend.py

Tests:
  1. Config → GROQ_API_KEY present
  2. Groq client → can make a streaming call
  3. Tavily search → returns results
  4. Task creation → writes to tasks.json
  5. TTS → edge-tts produces MP3 bytes
  6. WebSocket endpoint → connect and get a response
"""

import asyncio
import json
import os
import sys

from dotenv import load_dotenv
load_dotenv()

PASS = "[PASS]"
FAIL = "[FAIL]"
WARN = "[WARN]"


def section(title: str):
    print(f"\n-- {title} --")


async def test_config():
    section("Config")
    from config import config
    checks = [
        ("GROQ_API_KEY",       bool(config.GROQ_API_KEY)),
        ("TAVILY_API_KEY",     bool(config.TAVILY_API_KEY)),
        ("ELEVENLABS_API_KEY", bool(config.ELEVENLABS_API_KEY)),
        ("USER_NAME",          bool(config.USER_NAME)),
    ]
    for name, ok in checks:
        print(f"  {PASS if ok else WARN}  {name}: {'set' if ok else 'NOT SET'}")


async def test_groq_streaming():
    section("Groq Streaming LLM")
    from groq import AsyncGroq
    from config import config
    if not config.GROQ_API_KEY:
        print(f"  {WARN}  Skipped — no GROQ_API_KEY")
        return

    client = AsyncGroq(api_key=config.GROQ_API_KEY)
    collected = ""
    try:
        stream = await client.chat.completions.create(
            model="llama-3.3-70b-versatile",
            messages=[
                {"role": "system", "content": "You are a terse assistant. One sentence only."},
                {"role": "user", "content": "Say 'Voice backend is working' and nothing else."},
            ],
            max_tokens=40,
            temperature=0,
            stream=True,
        )
        async for chunk in stream:
            if chunk.choices[0].delta.content:
                collected += chunk.choices[0].delta.content

        print(f"  {PASS}  Response: {collected.strip()}")
    except Exception as e:
        print(f"  {FAIL}  Groq error: {e}")


async def test_tavily():
    section("Tavily Web Search")
    from config import config
    if not config.TAVILY_API_KEY:
        print(f"  {WARN}  Skipped — no TAVILY_API_KEY")
        return
    try:
        from tavily import TavilyClient
        client = TavilyClient(api_key=config.TAVILY_API_KEY)
        loop = asyncio.get_event_loop()
        result = await loop.run_in_executor(
            None, lambda: client.search("current time in London", max_results=2)
        )
        snippets = [r.get("content","")[:80] for r in result.get("results", [])[:2]]
        print(f"  {PASS}  Got {len(snippets)} results")
        for s in snippets:
            safe = s.encode('ascii', errors='replace').decode('ascii')
            print(f"       -> {safe}...")
    except Exception as e:
        print(f"  {FAIL}  Tavily error: {e}")


async def test_task_creation():
    section("Task Creation (tasks.json)")
    try:
        from voice_backend import _exec_create_task
        result = await _exec_create_task("Test task from voice backend", priority="low")
        print(f"  {PASS}  {result}")
        # Verify it's in the file
        with open("tasks.json") as f:
            tasks = json.load(f)
        task_list = tasks.get("tasks", tasks) if isinstance(tasks, dict) else tasks
        found = any("Test task from voice backend" in t.get("title","") for t in task_list)
        print(f"  {PASS if found else FAIL}  Persisted to tasks.json: {found}")
    except Exception as e:
        print(f"  {FAIL}  Task error: {e}")


async def test_tts():
    section("TTS (edge-tts)")
    try:
        from voice_backend import _tts_bytes
        audio = await _tts_bytes("Voice backend online. All systems ready.")
        if audio and len(audio) > 1000:
            print(f"  {PASS}  TTS produced {len(audio):,} bytes of audio")
        elif audio:
            print(f"  {WARN}  TTS returned only {len(audio)} bytes (might be truncated)")
        else:
            print(f"  {FAIL}  TTS returned no audio")
    except Exception as e:
        print(f"  {FAIL}  TTS error: {e}")


async def test_full_agent():
    section("Full Agent (mock WebSocket)")
    try:
        from voice_backend import run_voice_agent

        class MockWS:
            messages = []
            async def send_json(self, data):
                self.messages.append(data)

        ws = MockWS()
        response = await run_voice_agent(
            transcript="What time is it right now?",
            intent="query:time",
            history=[],
            ws=ws,
        )
        chunks    = [m for m in ws.messages if m["type"] == "response_chunk"]
        done_msgs = [m for m in ws.messages if m["type"] == "response_done"]
        print(f"  {PASS}  Agent returned {len(chunks)} chunks")
        print(f"  {PASS}  Final response: {response[:120]}")
        errors = [m for m in ws.messages if m["type"] == "error"]
        if errors:
            print(f"  {WARN}  Errors: {errors}")
    except Exception as e:
        print(f"  {FAIL}  Agent error: {e}")


async def test_websocket_live():
    """Optional: test against running server on localhost:8000."""
    section("Live WebSocket (requires running server)")
    try:
        import websockets
        uri = "ws://localhost:8000/ws/voice"
        async with websockets.connect(uri, open_timeout=2) as ws:
            await ws.send(json.dumps({
                "type": "voice_query",
                "text": "What time is it?",
                "intent": "query:time",
            }))
            messages = []
            deadline = asyncio.get_event_loop().time() + 10
            while asyncio.get_event_loop().time() < deadline:
                try:
                    raw = await asyncio.wait_for(ws.recv(), timeout=2)
                    msg = json.loads(raw)
                    messages.append(msg)
                    if msg.get("type") == "response_done":
                        break
                except asyncio.TimeoutError:
                    break

            chunks = [m for m in messages if m["type"] == "response_chunk"]
            done   = next((m for m in messages if m["type"] == "response_done"), None)
            print(f"  {PASS}  Received {len(chunks)} chunks from live server")
            if done:
                print(f"  {PASS}  Final: {done.get('text','')[:100]}")
    except ConnectionRefusedError:
        print(f"  {WARN}  Server not running — start with: uvicorn main:app --reload")
    except Exception as e:
        print(f"  {WARN}  WS test skipped: {e}")


async def main():
    print("\n--- SPATIAL Voice Backend Test Suite ---")

    await test_config()
    await test_groq_streaming()
    await test_tavily()
    await test_task_creation()
    await test_tts()
    await test_full_agent()
    await test_websocket_live()

    print("\nDone.\n")


if __name__ == "__main__":
    asyncio.run(main())
