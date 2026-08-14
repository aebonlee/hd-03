/**
 * OG 이미지 생성기 (1200×630)
 *
 *   npm i -D sharp        # package.json에는 넣지 않는다 (CI 경량 유지)
 *   node scripts/generate-og-image.mjs
 *
 * 원본 SVG는 Dev_md/og-image.svg 로 함께 남긴다. 나중에 문구만 고쳐 다시 구울 수 있게.
 * qlmanage 썸네일은 1200×1200 정사각이라 쓸 수 없다.
 */
import { writeFileSync, mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "sharp";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");

// ---- 다른 사이트로 옮길 때는 이 객체만 고친다 ----
const CONFIG = {
  eyebrow: "DREAMIT BIZ · 수업 실습 예제",
  title: "hd-03 회원가입 실습",
  subtitle: "Supabase로 직접 만드는 회원가입 · 로그인",
  bullets: ["입력값 검사와 비밀번호 정책", "RLS로 남의 정보 차단", "트리거로 프로필 자동 생성"],
  domain: "aebonlee.github.io/hd-03",
  colors: {
    brand: "#0b372a",
    brand2: "#174f3d",
    accent: "#d9a441",
    text: "#ffffff",
    muted: "rgba(255,255,255,.72)",
  },
  out: resolve(ROOT, "og-image.png"),
  svgOut: resolve(ROOT, "Dev_md/og-image.svg"),
};

const esc = (s) =>
  s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

const { colors: c } = CONFIG;

const bullets = CONFIG.bullets
  .map((text, i) => {
    // 마지막 줄이 아래 도메인 칩(y 560~)과 겹치지 않게 시작점을 잡는다
    const y = 440 + i * 46;
    return `
    <circle cx="86" cy="${y - 6}" r="11" fill="rgba(255,255,255,.11)" />
    <text x="86" y="${y}" font-size="15" fill="${c.accent}" text-anchor="middle"
          font-family="Apple SD Gothic Neo, Noto Sans KR, sans-serif">✓</text>
    <text x="112" y="${y}" font-size="23" fill="${c.muted}"
          font-family="Apple SD Gothic Neo, Noto Sans KR, sans-serif">${esc(text)}</text>`;
  })
  .join("");

const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="${c.brand}" />
      <stop offset="100%" stop-color="${c.brand2}" />
    </linearGradient>
    <radialGradient id="glow" cx="88%" cy="12%" r="60%">
      <stop offset="0%" stop-color="${c.accent}" stop-opacity=".22" />
      <stop offset="100%" stop-color="${c.accent}" stop-opacity="0" />
    </radialGradient>
  </defs>

  <rect width="1200" height="630" fill="url(#bg)" />
  <rect width="1200" height="630" fill="url(#glow)" />

  <circle cx="1105" cy="70" r="300" fill="none" stroke="rgba(255,255,255,.10)" stroke-width="1" />
  <circle cx="60" cy="600" r="190" fill="none" stroke="rgba(255,255,255,.10)" stroke-width="1" />

  <rect x="70" y="66" width="54" height="54" rx="17"
        fill="rgba(255,255,255,.12)" stroke="rgba(255,255,255,.2)" />
  <text x="97" y="103" font-size="22" font-weight="800" fill="${c.text}" text-anchor="middle"
        font-family="Apple SD Gothic Neo, Noto Sans KR, sans-serif">hd</text>

  <text x="140" y="101" font-size="24" font-weight="700" fill="${c.text}"
        font-family="Apple SD Gothic Neo, Noto Sans KR, sans-serif">${esc(CONFIG.title)}</text>

  <text x="72" y="243" font-size="19" letter-spacing="4" fill="${c.accent}"
        font-family="Apple SD Gothic Neo, Noto Sans KR, sans-serif">${esc(CONFIG.eyebrow)}</text>

  <text x="70" y="330" font-size="76" font-weight="800" fill="${c.text}" letter-spacing="-3"
        font-family="Apple SD Gothic Neo, Noto Sans KR, sans-serif">${esc(CONFIG.title)}</text>

  <text x="72" y="394" font-size="30" fill="${c.muted}"
        font-family="Apple SD Gothic Neo, Noto Sans KR, sans-serif">${esc(CONFIG.subtitle)}</text>

  ${bullets}

  <rect x="70" y="556" width="${18 + CONFIG.domain.length * 11.4}" height="42" rx="21"
        fill="rgba(255,255,255,.10)" stroke="rgba(255,255,255,.18)" />
  <text x="88" y="583" font-size="19" fill="${c.muted}"
        font-family="Apple SD Gothic Neo, Noto Sans KR, sans-serif">${esc(CONFIG.domain)}</text>
</svg>`;

mkdirSync(dirname(CONFIG.svgOut), { recursive: true });
writeFileSync(CONFIG.svgOut, svg, "utf8");

await sharp(Buffer.from(svg)).resize(1200, 630).png().toFile(CONFIG.out);

const meta = await sharp(CONFIG.out).metadata();
console.log(`생성: ${CONFIG.out} (${meta.width}×${meta.height})`);
if (meta.width !== 1200 || meta.height !== 630) {
  throw new Error(`크기가 1200×630이 아니다: ${meta.width}×${meta.height}`);
}
