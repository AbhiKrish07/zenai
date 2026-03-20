"""
Spatial Voice Backend — FastAPI
================================
Fast, production-ready voice assistant backend.

Stack (all already in requirements.txt / .env):
  • Groq llama-3.3-70b-versatile  — primary LLM (sub-100ms TTFT)
  • Tavily                        — live web search
  • edge-tts                      — HD Microsoft Neural TTS (Jarvis voice)
  • ElevenLabs                    — premium TTS override (if key set)
  • Pinecone + Jina               — long-term memory
  • SQLite tasks.json             — task persistence
  • system_control.py             — Windows/Mac device control

WebSocket:  ws://host/ws/voice
REST:       POST /api/voice/chat
            GET  /api/voice/status
            POST /api/voice/tts
"""

import asyncio
import base64
import json
import logging
import os
import re
import time
from datetime import datetime
from typing import Optional, AsyncGenerator

import httpx
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel

from config import config
from voice_engine import (
    classify_intent, strip_wake_word, contains_wake_word,
    synthesize_speech, synthesize_speech_streaming, format_jarvis_response,
    get_voice_session, VoiceSession,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("spatial.voice_backend")

# ─────────────────────────────────────────────────────────────────────────────
#  LLM Client — Groq (fatest streaming LLM available)
# ─────────────────────────────────────────────────────────────────────────────
try:
    from groq import AsyncGroq
    groq_client = AsyncGroq(api_key=config.GROQ_API_KEY) if config.GROQ_API_KEY else None
except ImportError:
    groq_client = None
    logger.warning("groq package not installed")

VOICE_MODEL  = "llama-3.3-70b-versatile"   # ~300ms TTFT, smartest Groq model
FAST_MODEL   = "llama-3.1-8b-instant"       # ~80ms TTFT, for simple queries

# ─────────────────────────────────────────────────────────────────────────────
#  Tavily Search
# ─────────────────────────────────────────────────────────────────────────────
try:
    from tavily import TavilyClient
    tavily = TavilyClient(api_key=config.TAVILY_API_KEY) if config.TAVILY_API_KEY else None
except ImportError:
    tavily = None

# ─────────────────────────────────────────────────────────────────────────────
#  Memory Engine (Pinecone/SQLite)
# ─────────────────────────────────────────────────────────────────────────────
try:
    from memory_engine import MemoryEngine
    memory_engine = MemoryEngine()
    MEMORY_AVAILABLE = True
except Exception as e:
    memory_engine = None
    MEMORY_AVAILABLE = False
    logger.warning(f"Memory engine unavailable: {e}")

# ─────────────────────────────────────────────────────────────────────────────
#  System Control
# ─────────────────────────────────────────────────────────────────────────────
try:
    from system_control import SystemControl
    sys_ctrl = SystemControl()
    SYSCTRL_AVAILABLE = True
except Exception as e:
    sys_ctrl = None
    SYSCTRL_AVAILABLE = False
    logger.warning(f"SystemControl unavailable: {e}")

# ─────────────────────────────────────────────────────────────────────────────
#  System Prompt (voice-optimised)
# ─────────────────────────────────────────────────────────────────────────────
def _build_system_prompt(context_facts: str = "") -> str:
    now = datetime.now().strftime("%A, %B %d %Y — %I:%M %p")
    user = config.USER_NAME or "Boss"
    return f"""You are SPATIAL — {user}'s hyper-intelligent AI voice assistant, modelled on Jarvis from Iron Man.

CURRENT TIME: {now}
USER: {user}

## VOICE RESPONSE RULES (CRITICAL — you will be read aloud)
1. ULTRA-CONCISE: 1-3 sentences for simple queries. Never more than 5 sentences unless explicitly asked.
2. NO MARKDOWN: no asterisks, headers, bullet points, or code blocks. Plain spoken English only.
3. NO URLS: summarise web content verbally, never read URLs aloud.
4. DIRECT: no preambles like "Great question!" or "Sure, I can help with that!". Just answer.
5. NATURAL: speak as if talking directly. Use contractions (I'll, it's, you've).
6. COMMANDS: confirm briefly what you did. "Done" or "Task created" beats a paragraph.
7. BE PROACTIVE: if the user's request implies a follow-up, suggest it.

## PERSONALITY
Confident, dry wit, precise. A brilliant friend who happens to know everything and can control your devices.

## AVAILABLE CAPABILITIES
- Web search (real-time)
- Task & reminder creation
- Memory recall and storage
- Device control (volume, brightness, apps, screenshots — Windows)
- Calendar reading
- Spotify / media control
- Weather lookups

## CONTEXT
{context_facts if context_facts else "No stored context yet."}

When using a capability, say what you're doing first: "Searching..." / "Creating the task..." — then do it.
"""

# ─────────────────────────────────────────────────────────────────────────────
#  Tool Implementations — wired to real services
# ─────────────────────────────────────────────────────────────────────────────

async def _exec_web_search(query: str, max_results: int = 4) -> str:
    """Tavily search → concise spoken summary."""
    if not tavily:
        # Fallback: DuckDuckGo instant answer API
        try:
            async with httpx.AsyncClient(timeout=5) as c:
                import urllib.parse
                r = await c.get(
                    f"https://api.duckduckgo.com/?q={urllib.parse.quote(query)}&format=json&no_html=1"
                )
                d = r.json()
                abstract = d.get("AbstractText", "")
                related  = [t.get("Text","") for t in d.get("RelatedTopics", [])[:3] if isinstance(t, dict)]
                combined = abstract + (" ".join(related) if related else "")
                return combined[:600] or f"No instant answer found for: {query}"
        except Exception as e:
            return f"Search failed: {e}"

    try:
        loop   = asyncio.get_event_loop()
        result = await loop.run_in_executor(
            None,
            lambda: tavily.search(query, max_results=max_results, search_depth="basic")
        )
        snippets = [r.get("content", "")[:250] for r in result.get("results", [])[:3]]
        return "\n".join(snippets) or "No results found."
    except Exception as e:
        return f"Search error: {e}"


async def _exec_create_task(title: str, due: str = "", priority: str = "medium", notes: str = "") -> str:
    """Append task to tasks.json."""
    import json as _json
    task = {
        "id": str(int(time.time())),
        "title": title,
        "due": due,
        "priority": priority,
        "notes": notes,
        "done": False,
        "created": datetime.now().isoformat(),
    }
    tasks_path = os.path.join(os.path.dirname(__file__), "tasks.json")
    try:
        with open(tasks_path, "r") as f:
            tasks = _json.load(f)
        if isinstance(tasks, dict):
            tasks = tasks.get("tasks", [])
    except Exception:
        tasks = []
    tasks.append(task)
    with open(tasks_path, "w") as f:
        _json.dump({"tasks": tasks}, f, indent=2)
    return f"Task created: '{title}'" + (f" — due {due}" if due else "")


async def _exec_read_calendar(days_ahead: int = 7) -> str:
    """Read Google Calendar events (if integrated) or return placeholder."""
    try:
        from google_integration import get_upcoming_events
        events = await get_upcoming_events(days=days_ahead)
        if not events:
            return "No upcoming events in the next week."
        lines = [f"{e.get('start','')} — {e.get('summary','')}" for e in events[:5]]
        return "Coming up: " + "; ".join(lines)
    except Exception:
        return "Calendar integration not connected. Add your Google credentials to use this."


async def _exec_get_memory(query: str) -> str:
    """Query long-term memory store."""
    if not MEMORY_AVAILABLE or not memory_engine:
        return "Memory not configured."
    try:
        loop    = asyncio.get_event_loop()
        results = await loop.run_in_executor(None, lambda: memory_engine.search(query, top_k=3))
        if not results:
            return f"No stored memories found for '{query}'."
        return " | ".join([r.get("content","") for r in results[:3]])
    except Exception as e:
        return f"Memory lookup failed: {e}"


async def _exec_save_memory(content: str, category: str = "general") -> str:
    """Save a fact to long-term memory."""
    if not MEMORY_AVAILABLE or not memory_engine:
        return "Memory not configured — I'll remember this for this session only."
    try:
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(
            None,
            lambda: memory_engine.add(content, metadata={"category": category, "ts": datetime.now().isoformat()})
        )
        return f"Stored in memory: {content}"
    except Exception as e:
        return f"Memory save failed: {e}"


async def _exec_control_media(action: str, query: str = "") -> str:
    """Spotify playback control via existing system_control."""
    if not SYSCTRL_AVAILABLE or not sys_ctrl:
        return f"Media control unavailable on this system."
    try:
        loop = asyncio.get_event_loop()
        if action == "play" and query:
            result = await loop.run_in_executor(None, lambda: sys_ctrl.spotify_play(query))
        elif action == "pause":
            result = await loop.run_in_executor(None, sys_ctrl.spotify_pause)
        elif action == "next":
            result = await loop.run_in_executor(None, sys_ctrl.media_next)
        elif action == "previous":
            result = await loop.run_in_executor(None, sys_ctrl.media_previous)
        elif action == "volume_up":
            result = await loop.run_in_executor(None, lambda: sys_ctrl.set_volume("+10"))
        elif action == "volume_down":
            result = await loop.run_in_executor(None, lambda: sys_ctrl.set_volume("-10"))
        else:
            result = f"Unknown media action: {action}"
        return str(result) if result else f"Media {action} executed"
    except Exception as e:
        return f"Media control error: {e}"


async def _exec_set_reminder(message: str, when: str) -> str:
    """Create a timed reminder (stored as task with due time)."""
    return await _exec_create_task(
        title=f"⏰ REMINDER: {message}",
        due=when,
        priority="high",
    )


async def _exec_device_control(action: str, value: str = "") -> str:
    """Direct device control — volume, brightness, screenshot, open app."""
    if not SYSCTRL_AVAILABLE or not sys_ctrl:
        return f"Device control unavailable on this system."
    try:
        loop = asyncio.get_event_loop()
        if action == "volume":
            v = int(value) if str(value).isdigit() else 50
            result = await loop.run_in_executor(None, lambda: sys_ctrl.set_volume(v))
        elif action == "brightness":
            b = int(value) if str(value).isdigit() else 70
            result = await loop.run_in_executor(None, lambda: sys_ctrl.set_brightness(b))
        elif action == "screenshot":
            result = await loop.run_in_executor(None, sys_ctrl.take_screenshot)
        elif action == "open_app":
            result = await loop.run_in_executor(None, lambda: sys_ctrl.open_app(value))
        elif action == "lock":
            result = await loop.run_in_executor(None, sys_ctrl.lock_screen)
        else:
            result = f"Unknown device action: {action}"
        return str(result) if result else f"Done: {action}"
    except Exception as e:
        return f"Device control error: {e}"


async def _exec_get_weather(city: str = "") -> str:
    """OpenWeatherMap current conditions."""
    city = city or config.USER_CITY or "London"
    apikey = config.OPENWEATHER_API_KEY
    if not apikey:
        return "Weather API key not configured."
    try:
        async with httpx.AsyncClient(timeout=5) as c:
            r = await c.get(
                "https://api.openweathermap.org/data/2.5/weather",
                params={"q": city, "appid": apikey, "units": "metric"}
            )
            d = r.json()
            desc  = d["weather"][0]["description"]
            temp  = d["main"]["temp"]
            feels = d["main"]["feels_like"]
            return f"In {city}: {desc}, {temp:.0f}°C, feels like {feels:.0f}°C."
    except Exception as e:
        return f"Weather unavailable: {e}"


# ─────────────────────────────────────────────────────────────────────────────
#  Tool Router
# ─────────────────────────────────────────────────────────────────────────────
TOOLS = {
    "web_search":     lambda inp: _exec_web_search(inp.get("query",""), inp.get("max_results", 4)),
    "create_task":    lambda inp: _exec_create_task(inp.get("title",""), inp.get("due",""), inp.get("priority","medium"), inp.get("notes","")),
    "read_calendar":  lambda inp: _exec_read_calendar(inp.get("days_ahead", 7)),
    "get_memory":     lambda inp: _exec_get_memory(inp.get("query","")),
    "save_memory":    lambda inp: _exec_save_memory(inp.get("content",""), inp.get("category","general")),
    "control_media":  lambda inp: _exec_control_media(inp.get("action","pause"), inp.get("query","")),
    "set_reminder":   lambda inp: _exec_set_reminder(inp.get("message",""), inp.get("when","")),
    "device_control": lambda inp: _exec_device_control(inp.get("action",""), inp.get("value","")),
    "get_weather":    lambda inp: _exec_get_weather(inp.get("city","")),
}

async def exec_tool(name: str, inp: dict) -> str:
    fn = TOOLS.get(name)
    if not fn:
        return f"Unknown tool: {name}"
    try:
        return await fn(inp)
    except Exception as e:
        logger.error(f"Tool {name} error: {e}")
        return f"Error in {name}: {e}"


# ─────────────────────────────────────────────────────────────────────────────
#  Groq Tool Definitions (function-calling schema)
# ─────────────────────────────────────────────────────────────────────────────
GROQ_TOOLS = [
    {"type": "function", "function": {
        "name": "web_search",
        "description": "Search the web for real-time information, news, facts, prices, anything current.",
        "parameters": {"type": "object", "properties": {
            "query": {"type": "string"},
            "max_results": {"type": "integer", "default": 4}
        }, "required": ["query"]}
    }},
    {"type": "function", "function": {
        "name": "create_task",
        "description": "Create a task, to-do, or action item for the user.",
        "parameters": {"type": "object", "properties": {
            "title": {"type": "string"},
            "due":   {"type": "string", "description": "ISO date or natural language"},
            "priority": {"type": "string", "enum": ["low", "medium", "high", "critical"]},
            "notes": {"type": "string"}
        }, "required": ["title"]}
    }},
    {"type": "function", "function": {
        "name": "read_calendar",
        "description": "Read the user's upcoming calendar events.",
        "parameters": {"type": "object", "properties": {
            "days_ahead": {"type": "integer", "default": 7}
        }}
    }},
    {"type": "function", "function": {
        "name": "get_memory",
        "description": "Retrieve facts, preferences, or context the user has previously stored.",
        "parameters": {"type": "object", "properties": {
            "query": {"type": "string"}
        }, "required": ["query"]}
    }},
    {"type": "function", "function": {
        "name": "save_memory",
        "description": "Save an important fact, preference, or note to long-term memory.",
        "parameters": {"type": "object", "properties": {
            "content": {"type": "string"},
            "category": {"type": "string"}
        }, "required": ["content"]}
    }},
    {"type": "function", "function": {
        "name": "control_media",
        "description": "Control media playback: play, pause, next, previous, volume up/down.",
        "parameters": {"type": "object", "properties": {
            "action": {"type": "string", "enum": ["play","pause","next","previous","volume_up","volume_down"]},
            "query":  {"type": "string", "description": "What to play (optional)"}
        }, "required": ["action"]}
    }},
    {"type": "function", "function": {
        "name": "set_reminder",
        "description": "Set a timed reminder or alarm.",
        "parameters": {"type": "object", "properties": {
            "message": {"type": "string"},
            "when": {"type": "string"}
        }, "required": ["message", "when"]}
    }},
    {"type": "function", "function": {
        "name": "device_control",
        "description": "Control device: set volume/brightness, take screenshot, open an app, lock screen.",
        "parameters": {"type": "object", "properties": {
            "action": {"type": "string", "enum": ["volume","brightness","screenshot","open_app","lock"]},
            "value": {"type": "string", "description": "For volume/brightness: number 0-100. For open_app: app name."}
        }, "required": ["action"]}
    }},
    {"type": "function", "function": {
        "name": "get_weather",
        "description": "Get current weather conditions for a city.",
        "parameters": {"type": "object", "properties": {
            "city": {"type": "string"}
        }}
    }},
]


# ─────────────────────────────────────────────────────────────────────────────
#  Core Agentic Loop — Groq streaming with tool use
# ─────────────────────────────────────────────────────────────────────────────
async def run_voice_agent(
    transcript: str,
    intent: str,
    history: list,
    ws: WebSocket,
) -> str:
    """
    Groq streaming agentic loop.
    Returns the final text response so it can be added to history.
    """
    if not groq_client:
        msg = "AI backend not configured. Set GROQ_API_KEY in .env"
        await ws.send_json({"type": "response_done", "text": msg})
        return msg

    system = _build_system_prompt()
    messages = list(history[-8:])   # Keep last 4 turns for context
    messages.append({"role": "user", "content": transcript})

    final_text = ""
    max_iter   = 5
    iteration  = 0

    while iteration < max_iter:
        iteration += 1
        logger.info(f"[Voice] Agent iteration {iteration}, model={VOICE_MODEL}")

        try:
            # ── Streaming call to Groq ──────────────────────────────────
            stream = await groq_client.chat.completions.create(
                model=VOICE_MODEL,
                messages=[{"role": "system", "content": system}] + messages,
                tools=GROQ_TOOLS,
                tool_choice="auto",
                max_tokens=400,     # Keep voice responses short
                temperature=0.35,
                stream=True,
            )

            current_text    = ""
            tool_calls_acc: dict[str, dict] = {}  # id → {name, arguments}

            async for chunk in stream:
                delta = chunk.choices[0].delta if chunk.choices else None
                if not delta:
                    continue

                # Stream text chunks
                if delta.content:
                    current_text += delta.content
                    final_text   += delta.content
                    await ws.send_json({"type": "response_chunk", "text": delta.content})

                # Accumulate tool call deltas
                if delta.tool_calls:
                    for tc in delta.tool_calls:
                        cid = tc.index
                        if cid not in tool_calls_acc:
                            tool_calls_acc[cid] = {"id": tc.id or f"tc_{cid}", "name": "", "arguments": ""}
                        if tc.function:
                            if tc.function.name:
                                tool_calls_acc[cid]["name"] = tc.function.name
                            if tc.function.arguments:
                                tool_calls_acc[cid]["arguments"] += tc.function.arguments

            finish_reason = chunk.choices[0].finish_reason if chunk.choices else "stop"

            if finish_reason == "tool_calls" and tool_calls_acc:
                # ── Execute each tool call ──────────────────────────────
                tool_messages = []
                for tc in tool_calls_acc.values():
                    name = tc["name"]
                    try:
                        inp = json.loads(tc["arguments"]) if tc["arguments"] else {}
                    except json.JSONDecodeError:
                        inp = {}

                    logger.info(f"[Voice] Tool call: {name}({inp})")
                    await ws.send_json({"type": "tool_start", "tool": name})

                    result = await exec_tool(name, inp)

                    await ws.send_json({"type": "tool_done", "tool": name, "result": result[:300]})
                    tool_messages.append({
                        "role": "tool",
                        "tool_call_id": tc["id"],
                        "content": result,
                    })

                # Add assistant + tool results to message history
                tool_call_objs = [
                    {"id": tc["id"], "type": "function",
                     "function": {"name": tc["name"], "arguments": tc["arguments"]}}
                    for tc in tool_calls_acc.values()
                ]
                messages.append({
                    "role": "assistant",
                    "content": current_text or None,
                    "tool_calls": tool_call_objs,
                })
                messages.extend(tool_messages)
                # Reset for next iteration
                final_text = ""

            else:
                # Done
                break

        except Exception as e:
            logger.error(f"[Voice] Agent error (iter={iteration}): {e}")
            err_msg = f"I ran into a technical issue. {str(e)[:100]}"
            await ws.send_json({"type": "error", "message": str(e)})
            await ws.send_json({"type": "response_done", "text": err_msg})
            return err_msg

    final_text = final_text.strip()
    await ws.send_json({"type": "response_done", "text": final_text})
    logger.info(f"[Voice] Done. Response: {final_text[:80]}...")
    return final_text


# ─────────────────────────────────────────────────────────────────────────────
#  TTS Helper — ElevenLabs → edge-tts → none
# ─────────────────────────────────────────────────────────────────────────────
async def _tts_bytes(text: str) -> Optional[bytes]:
    """Get TTS audio bytes — tries ElevenLabs first, then edge-tts."""
    el_key    = config.ELEVENLABS_API_KEY
    el_voice  = config.ELEVENLABS_VOICE_ID
    clean     = format_jarvis_response(text, add_prefix=False)
    if not clean:
        return None

    if el_key and el_key != "sk_REPLACE_ME":
        try:
            async with httpx.AsyncClient(timeout=10) as c:
                r = await c.post(
                    f"https://api.elevenlabs.io/v1/text-to-speech/{el_voice}",
                    headers={"xi-api-key": el_key, "Content-Type": "application/json"},
                    json={"text": clean, "model_id": "eleven_turbo_v2",
                          "voice_settings": {"stability": 0.5, "similarity_boost": 0.8}}
                )
                if r.status_code == 200:
                    return r.content
        except Exception as e:
            logger.warning(f"ElevenLabs TTS failed: {e}")

    # Fallback: edge-tts
    return await synthesize_speech(clean, voice="en-US-GuyNeural")


# ─────────────────────────────────────────────────────────────────────────────
#  FastAPI Router
# ─────────────────────────────────────────────────────────────────────────────
voice_router = APIRouter(prefix="/api/voice", tags=["voice"])


class ChatRequest(BaseModel):
    text: str
    intent: str = "conversation"
    history: list = []
    tts: bool = False


@voice_router.post("/chat")
async def voice_chat_rest(req: ChatRequest):
    """REST fallback for voice chat (no streaming)."""
    if not groq_client:
        raise HTTPException(503, "GROQ_API_KEY not configured")

    system   = _build_system_prompt()
    messages = req.history[-8:] + [{"role": "user", "content": req.text}]
    try:
        resp = await groq_client.chat.completions.create(
            model=VOICE_MODEL,
            messages=[{"role": "system", "content": system}] + messages,
            max_tokens=300,
            temperature=0.35,
        )
        text = resp.choices[0].message.content.strip()
    except Exception as e:
        raise HTTPException(500, str(e))

    result: dict = {"response": text, "intent": req.intent}
    if req.tts:
        audio = await _tts_bytes(text)
        if audio:
            result["audio_b64"] = base64.b64encode(audio).decode()
            result["audio_mime"] = "audio/mpeg"
    return result


@voice_router.post("/tts")
async def voice_tts(text: str):
    """Synthesise speech and return MP3 bytes."""
    audio = await _tts_bytes(text)
    if not audio:
        raise HTTPException(503, "TTS unavailable — install edge-tts or set ELEVENLABS_API_KEY")
    return Response(content=audio, media_type="audio/mpeg")


@voice_router.get("/status")
async def voice_status():
    session = get_voice_session()
    return {
        "status": "ok",
        "groq": bool(groq_client),
        "tavily": bool(tavily),
        "memory": MEMORY_AVAILABLE,
        "sysctrl": SYSCTRL_AVAILABLE,
        "elevenlabs": bool(config.ELEVENLABS_API_KEY),
        "model": VOICE_MODEL,
        "session": session.to_dict(),
        "timestamp": datetime.utcnow().isoformat(),
    }


# ─────────────────────────────────────────────────────────────────────────────
#  WebSocket Endpoint  — /ws/voice
# ─────────────────────────────────────────────────────────────────────────────
async def voice_ws_endpoint(websocket: WebSocket):
    """
    Real-time voice WebSocket handler.

    Message protocol (client → server):
      { "type": "voice_query", "text": "...", "intent": "...", "is_command": bool }
      { "type": "ping" }

    Message protocol (server → client):
      { "type": "processing_start", "text": "..." }
      { "type": "tool_start", "tool": "web_search" }
      { "type": "tool_done",  "tool": "web_search", "result": "..." }
      { "type": "response_chunk", "text": "..." }
      { "type": "response_done",  "text": "full text", "audio_b64": "..." }
      { "type": "error", "message": "..." }
      { "type": "pong" }
    """
    await websocket.accept()
    logger.info(f"[Voice WS] Connected: {websocket.client}")

    history: list = []
    session = get_voice_session()
    session.active = True

    try:
        while True:
            raw  = await websocket.receive_text()
            data = json.loads(raw)
            mtype = data.get("type", "")

            if mtype == "ping":
                await websocket.send_json({"type": "pong"})
                continue

            if mtype == "voice_query":
                transcript = data.get("text", "").strip()
                intent     = data.get("intent", "conversation")

                if not transcript:
                    continue

                session.listening  = False
                logger.info(f"[Voice WS] Query: '{transcript}' intent={intent}")

                await websocket.send_json({
                    "type": "processing_start",
                    "text": transcript,
                })

                # Run the agentic loop
                response_text = await run_voice_agent(
                    transcript=transcript,
                    intent=intent,
                    history=history,
                    ws=websocket,
                )

                # Update conversation history
                history.append({"role": "user",      "content": transcript})
                history.append({"role": "assistant",  "content": response_text})
                if len(history) > 20:
                    history = history[-20:]

                session.record_interaction(transcript, response_text)

                # Optionally send TTS audio for mobile clients
                # (client-side TTS is preferred for low latency; this is backup)
                # audio = await _tts_bytes(response_text)
                # if audio:
                #     await websocket.send_json({
                #         "type": "tts_audio",
                #         "audio_b64": base64.b64encode(audio).decode(),
                #         "mime": "audio/mpeg",
                #     })

    except WebSocketDisconnect:
        logger.info("[Voice WS] Disconnected")
    except Exception as e:
        logger.error(f"[Voice WS] Error: {e}", exc_info=True)
        try:
            await websocket.send_json({"type": "error", "message": str(e)})
        except Exception:
            pass
    finally:
        session.active = False
