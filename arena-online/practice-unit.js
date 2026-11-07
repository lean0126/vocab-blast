/* VOCAB BLAST V6: require a teacher-selected Unit before any classic practice mode. */
(async () => {
  'use strict';
  const app = document.getElementById('app');
  const show = (msg, retry=false) => {
    app.innerHTML = '<div style="max-width:650px;margin:90px auto;padding:28px;border-radius:22px;background:#202444;color:#fff;font:17px Arial;line-height:1.6"><h2>📚 Từ vựng theo Unit</h2><p id="practice-msg"></p><p><a href="online.html" style="color:#8eeaff">Vào ARENA ONLINE để đăng nhập / chọn Unit</a></p>'+(retry?'<button id="practice-retry" style="padding:12px 20px;cursor:pointer">Thử lại</button>':'')+'</div>';
    document.getElementById('practice-msg').textContent = msg;
    if(retry) document.getElementById('practice-retry').onclick=()=>location.reload();
  };
  try {
    show('Đang tải Unit cô giáo đã chọn...');
    const cfg = window.ARENA_CONFIG;
    if(!cfg?.url || !cfg?.anonKey || !window.supabase?.createClient) throw Error('Không tải được cấu hình hoặc thư viện Supabase');
    const db = window.supabase.createClient(cfg.url,cfg.anonKey);
    const {data:{session},error:authErr}=await db.auth.getSession();
    if(authErr) throw authErr;
    if(!session) throw Error('Hãy đăng nhập và tham gia lớp trong ARENA ONLINE trước khi luyện tập.');
    const requestedClass=new URLSearchParams(location.search).get('class');
    const {data,error}=await db.rpc('practice_active_unit',{p_class:requestedClass||null});
    if(error) throw error;
    if(!data?.words || data.words.length<10) throw Error('Unit chưa đủ 10 từ vựng');
    // This replaces the old built-in word bank entirely, including distractors and local duels.
    window.WORDS=data.words.map(w=>({en:String(w.en).trim(),vi:String(w.vi).trim(),emoji:'📖',level:'easy'}));
    const banner=document.createElement('div');
    banner.style.cssText='position:relative;z-index:3;text-align:center;padding:8px;background:#132b43;color:#d4f9ff;font:700 14px Arial';
    banner.textContent='📚 '+data.class_name+' · '+data.unit_name+' · '+data.words.length+' từ';
    document.body.insertBefore(banner,document.body.firstChild);
    const script=document.createElement('script');script.src='app.js?v=6';script.onerror=()=>show('Không tải được app.js. Kiểm tra đường dẫn trên GitHub.',true);
    document.body.appendChild(script);
  }catch(e){show(e.message||String(e),true);}
})();
