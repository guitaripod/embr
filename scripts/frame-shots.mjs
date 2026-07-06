// Frames raw 1320x2868 app captures into App Store / marketing screenshots that
// match the existing Embr store style: purple gradient, bold headline, a rounded
// device screenshot floated below. Run with the midgarcorp canvas available:
//   NODE_PATH=~/Dev/web/midgarcorp/node_modules node scripts/frame-shots.mjs
import fs from 'node:fs'
import path from 'node:path'
import { createRequire } from 'node:module'
const require = createRequire('/Users/marcus/Dev/web/midgarcorp/')
const { createCanvas, loadImage } = require('canvas')

const W = 1320
const H = 2868
const SRC = '/tmp/embr-caps'
const OUT = '/tmp/embr-framed'
fs.mkdirSync(OUT, { recursive: true })

// raw file (in SRC) -> headline (max 2 lines). Order = store display order.
const SHOTS = [
  { file: 'top.png', headline: 'Every live channel,\nat a glance' },
  { file: 'following.png', headline: 'Your channels,\none tap away' },
  { file: 'chatonly.png', headline: 'Native chat with\n7TV, BTTV & FFZ' },
  { file: 'audio.png', headline: 'Listen in the\nbackground' },
  { file: 'categories.png', headline: 'Browse by category' },
  { file: 'search.png', headline: 'Find channels\nand games instantly' },
  { file: 'settings.png', headline: 'Make it yours' },
  { file: 'onboarding.png', headline: 'A native Twitch\nclient for iPhone' },
]

function roundedTopRect(ctx, x, y, w, h, r) {
  ctx.beginPath()
  ctx.moveTo(x + r, y)
  ctx.arcTo(x + w, y, x + w, y + r, r)
  ctx.lineTo(x + w, y + h)
  ctx.lineTo(x, y + h)
  ctx.lineTo(x, y + r)
  ctx.arcTo(x, y, x + r, y, r)
  ctx.closePath()
}

async function frame({ file, headline }) {
  const canvas = createCanvas(W, H)
  const ctx = canvas.getContext('2d')

  // gradient background
  const g = ctx.createLinearGradient(0, 0, 0, H)
  g.addColorStop(0.0, '#6A32C8')
  g.addColorStop(0.32, '#3C2374')
  g.addColorStop(0.62, '#1E1440')
  g.addColorStop(1.0, '#140E26')
  ctx.fillStyle = g
  ctx.fillRect(0, 0, W, H)

  // headline
  const lines = headline.split('\n')
  ctx.fillStyle = '#FFFFFF'
  ctx.textAlign = 'center'
  ctx.textBaseline = 'middle'
  const fontSize = 96
  const lineHeight = 116
  ctx.font = `700 ${fontSize}px "SF Pro Display", "Helvetica Neue", Helvetica, Arial`
  const blockTop = 250
  lines.forEach((line, i) => {
    ctx.fillText(line, W / 2, blockTop + i * lineHeight)
  })

  // device screenshot: near-full-width, rounded top, floated below headline, running off the bottom
  const shot = await loadImage(path.join(SRC, file))
  const targetW = 1096
  const scale = targetW / shot.width
  const targetH = shot.height * scale
  const x = (W - targetW) / 2
  const y = 470
  const radius = 52

  // soft shadow
  ctx.save()
  ctx.shadowColor = 'rgba(0,0,0,0.45)'
  ctx.shadowBlur = 60
  ctx.shadowOffsetY = 24
  roundedTopRect(ctx, x, y, targetW, Math.min(targetH, H - y), radius)
  ctx.fillStyle = '#000'
  ctx.fill()
  ctx.restore()

  // clip + draw the screenshot
  ctx.save()
  roundedTopRect(ctx, x, y, targetW, targetH, radius)
  ctx.clip()
  ctx.drawImage(shot, x, y, targetW, targetH)
  ctx.restore()

  const out = path.join(OUT, file)
  fs.writeFileSync(out, canvas.toBuffer('image/png'))
  console.log('framed', file)
}

for (const s of SHOTS) await frame(s)
console.log('done ->', OUT)
