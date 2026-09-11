// dress-your-agent: asar 内容补丁
// 用法: node asar-patch.js <解包后的asar目录> <壁纸文件名> <是否强制深色 true|false>
const fs = require("fs");
const path = require("path");

const work = process.argv[2];
const img = process.argv[3] || "bg-custom.jpg";
const forceDark = (process.argv[4] || "true") === "true";
if (!work) { console.error("usage: node asar-patch.js <workDir> <imgName> <forceDark>"); process.exit(1); }

// ---- 1. 主窗口 index.html：壁纸样式（标题栏区域） ----
const htmlPath = path.join(work, ".vite", "renderer", "main_window", "index.html");
let html = fs.readFileSync(htmlPath, "utf8");
if (!html.includes("bg-patch-style")) {
  const css = `
<style id="bg-patch-style">
@media (prefers-color-scheme: dark) {
  html, body { background: transparent !important; }
  body::before {
    content: ""; position: fixed; inset: 0; z-index: -1; pointer-events: none;
    background: linear-gradient(rgba(10,12,18,.45), rgba(10,12,18,.45)),
                url("./assets/${img}") center/cover no-repeat;
  }
}
</style>
</head>`;
  html = html.replace("</head>", css);
  fs.writeFileSync(htmlPath, html);
  console.log("index.html: wallpaper style injected");
} else console.log("index.html: already patched");

// ---- 2. 主进程 index.pre.js：强制深色 + 页面透明化注入 ----
const prePath = path.join(work, ".vite", "build", "index.pre.js");
let pre = fs.readFileSync(prePath, "utf8");
if (pre.includes("__dressYourAgent")) {
  console.log("index.pre.js: already patched");
} else {
  const darkLine = forceDark
    ? `electron.nativeTheme.themeSource="dark";`
    : `/* follow system theme */`;
  pre += `
;(function(){try{
if(globalThis.__dressYourAgent)return;globalThis.__dressYourAgent=true;
var electron=require("electron");
${darkLine}
var fs=require("fs"),pathm=require("path");
var css=fs.readFileSync(pathm.join(__dirname,"theme-remote.css"),"utf8");
var apply=function(wc){try{wc.insertCSS(css,{cssOrigin:"author"});}catch(e){}};
var app=electron.app;
app.on("web-contents-created",function(_e,wc){
  wc.on("dom-ready",function(){setTimeout(function(){apply(wc);},80);});
  wc.on("did-navigate",function(){setTimeout(function(){apply(wc);},120);});
});
}catch(err){}})();
`;
  fs.writeFileSync(prePath, pre);
  console.log("index.pre.js: hook installed (forceDark=" + forceDark + ")");
}

// ---- 3. 运行时注入用的透明化样式 ----
const cssPath = path.join(work, ".vite", "build", "theme-remote.css");
fs.writeFileSync(cssPath, `/* dress-your-agent runtime injection (dark only) */
html[data-mode="dark"] body, html.dark body, html[data-theme="dark"] body {
  background-color: transparent !important;
  background: transparent !important;
}
html[data-mode="dark"] #root, html[data-mode="dark"] [id*="root"], html[data-mode="dark"] main {
  background: transparent !important;
}
`);
console.log("theme-remote.css written");
