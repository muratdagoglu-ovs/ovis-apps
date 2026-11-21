const paths={
home:'M3 10 12 3l9 7v10h-6v-6H9v6H3z',plan:'M4 6h16v15H4z M8 3v6m8-6v6M7 12h10m-10 4h7',drop:'M12 2s-7 8-7 13a7 7 0 0 0 14 0c0-5-7-13-7-13z',chart:'M3 3v17h18M6 15l5-6 4 3 5-7',camera:'M3 7h4l2-3h6l2 3h4v13H3z M16 13a4 4 0 1 1-8 0 4 4 0 0 1 8 0z',walk:'M14 5a2 2 0 1 1 0-4 2 2 0 0 1 0 4z M6 12l4-4 3-1 3 5 4 1 M12 9l-2 6 4 3 1 4m-5-7-5 7',left:'m14 5-7 7 7 7',next:'m9 5 7 7-7 7',food:'M5 3v6q0 4 3 4t3-4V3M8 3v18m10-18q-4 5-3 10h4m0-10v18',check:'m3 12 6 6L21 5',adjust:'M3 7h6m4 0h8M3 17h10m4 0h4 M13 7a2 2 0 1 1-4 0 2 2 0 1 1 4 0z M17 17a2 2 0 1 1-4 0 2 2 0 1 1 4 0z',leaf:'M4 18C-1 8 8 3 21 3c0 13-6 19-15 15m-2 3 11-12',clock:'M21 12a9 9 0 1 1-18 0 9 9 0 1 1 18 0z M12 6v6l4 2',user:'M16 7a4 4 0 1 1-8 0 4 4 0 1 1 8 0zM4 21c1-9 15-9 16 0',up:'m4 16 7-7 4 4 6-7m-5 0h5v5',down:'m4 8 7 7 4-4 6 7m-5 0h5v-5',steady:'M3 12h18m-5-5 5 5-5 5',image:'M3 4h18v16H3zM3 17l6-6 4 4 3-3 5 5',shoe:'M3 12V7l5 1 2 4 6 2 4 1 1 4H3z',plus:'M12 4v16M4 12h16',cup:'M5 4h14l-2 16H7z M6 10h12'};
const ic=n=>'<svg class="icon" aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="'+paths[n]+'"/></svg>';
const screens=['bugun','profil','hedef','plan','hareket','fotograf','analiz','degistir','su','odem','gelisim','antrenman'];
const S={age:35,height:175,weight:75,sex:'Kadın',goal:'Kilomu korumak',activity:'Orta',rice:150,oil:0,water:1000,other:250,restricted:false,drink:'Su',target:1750,mealSaved:false,walkDone:false,context:'Dışarıdayım',swap:false,added:false,waterlog:[],validProfile:true};
const navs=[['bugun','home','Bugün'],['plan','plan','Plan'],['antrenman','walk','Antrenman'],['su','drop','Su'],['gelisim','chart','Gelişim']];
const act=(name,js,cls='cta')=>'<button class="'+cls+'" onclick="'+js+'">'+name+'</button>';
const go=id=>"location.hash='"+id+"'";
const goto=(name,id,cls)=>act(name,go(id),cls);
const hd=(s,r='')=>'<div class="heading"><h2>'+s+'</h2>'+r+'</div>';
const bar=(back,r='')=>'<div class="bar">'+goto(ic('left'),back,'round')+r+'</div>';
const heading=(k,h)=>'<div class="k">'+k+'</div><h1 class="big">'+h+'</h1>';
const info=(head,body)=>'<div class="info"><b>'+head+'</b><span class="hint">'+body+'</span></div>';
const row=(icon,h,desc,right='')=>'<div class="line"><span class="ico">'+ic(icon)+'</span><div class="grow"><strong>'+h+'</strong><span class="dim">'+desc+'</span></div>'+right+'</div>';
const linkrow=(icon,h,d,id)=>goto(row(icon,h,d,ic('next')),id,'rowlink');
const format=n=>n.toLocaleString('tr-TR'), total=()=>S.water+S.other;
const lo=()=>250+Math.round(180*S.rice/150)+S.oil*9+(S.added?45:0),hi=()=>330+Math.round(230*S.rice/150)+S.oil*9+(S.added?65:0);
const range=()=>lo()+'–'+hi();
const word='<div class="word"><i class="mark"></i><span>Ovis <em>Fit</em></span></div>';
const ovi='<img alt="Ovi maskotu" src="Assets/ovi.png">';
const avatar=goto(ovi,'profil','avatar');
const photo=(cls='',label='')=>'<div class="photo '+cls+'"><img src="Assets/tabak.jpg" alt="Izgara tavuk, bulgur ve salata">'+(label?'<span class="cap">'+label+'</span>':'')+'</div>';
const meal=(name,sub,over='ÖĞLE · 13.00')=>'<button class="meal" onclick="'+go('plan')+'"><img src="Assets/tabak.jpg" alt=""><div><span class="k">'+over+'</span><strong>'+name+'</strong><span class="dim">'+sub+'</span></div></button>';
const tabnav=id=>'<nav class="nav">'+navs.map(([k,i,l])=>goto(ic(i)+l,k,k===id?'sel':'')).join('')+'</nav>';
const day='<div class="day">'+['Pzt','Sal','Çar','Per','Cum','Cmt','Paz'].map((s,i)=>'<span class="'+(i===4?'on':'')+'">'+s+'<b>'+(16+i)+'</b></span>').join('')+'</div>';
const goalBtns=()=>['Kilo vermek','Kilomu korumak','Kilo almak'].map((v,i)=>act('<span class="ico">'+ic(['down','steady','up'][i])+'</span>'+v+'<span>'+(S.goal===v?ic('check'):'○')+'</span>',"S.goal='"+v+"';render()",'choice '+(S.goal===v?'on':''))).join('');
const steps=n=>'<div class="ticks"><i class="on"></i><i class="'+(n===2?'on':'')+'"></i></div>';
function clickSave(){S.mealSaved=true;S.savedRange=[lo(),hi()];location.hash='bugun'}
function waterAdd(n){S.waterlog.push([S.drink,n]);if(S.drink==='Su')S.water+=n;else S.other+=n;render()}
function waterUndo(){let item=S.waterlog.pop();if(item){if(item[0]==='Su')S.water-=item[1];else S.other-=item[1]}render()}
const exercises = [
    { id: 'squat', place: 'Salon', name: 'Barbell squat', sets: '3 set × 8–10 tekrar' },
    { id: 'latpulldown', place: 'Salon', name: 'Lat pulldown', sets: '3 set × 10–12 tekrar' },
    { id: 'dbbench', place: 'Salon', name: 'Dambıl bench press', sets: '3 set × 8–12 tekrar' },
    { id: 'pushup', place: 'Ev', name: 'Şınav', sets: '3 set × 8–12 tekrar' },
    { id: 'glutebridge', place: 'Ev', name: 'Kalça köprüsü', sets: '3 set × 12–15 tekrar' }
];
let workoutPlace = 'Salon';
const mediaRoot = '../Prototip/iOS/Resources/';
function workoutPreview() {
    const list = exercises.filter(ex => ex.place === workoutPlace);
    const filters = ['Salon', 'Ev'].map(place =>
        act(place, "workoutPlace='" + place + "'; render()", place === workoutPlace ? 'on' : '')
    ).join('');
    const cards = list.map(ex => {
        const jpg = mediaRoot + 'Assets.xcassets/ovi-' + ex.id + '.imageset/poster.jpg';
        return '<section class="workout-card"><video controls playsinline muted loop preload="none" poster="' + jpg + '" aria-label="Ovi ile ' + ex.name + '"><source src="' + mediaRoot + 'WorkoutMedia/' + ex.id + '.mp4" type="video/mp4"></video><div><strong>' + ex.name + '</strong><span>' + ex.sets + '</span></div></section>';
    }).join('');
    return '<div class="bar">' + word + avatar + '</div>' +
        heading('Antrenman', 'Bugünün <span class="serif">programı.</span>') + '<div class="seg">' + filters + '</div>' +
        '<div class="training-cover"><b>' + workoutPlace + '</b><span>' + list.length + ' hareket · ' + (list.length * 3) + ' set</span></div>' + cards;
}

function render(){
const id=location.hash.slice(1)||'bugun';if(!screens.includes(id)){location.hash='bugun';return}
let html='',foot='';
if(id==='antrenman'){html=workoutPreview();foot=tabnav(id)}
if(id==='bugun'){
const energy=S.mealSaved?1240+Math.round((S.savedRange[0]+S.savedRange[1])/2):1240,pct=Math.round(100*energy/2100);
html='<div class="bar">'+word+avatar+'</div>'+heading('20 Kasım · Cuma','Günaydın, <span class="serif">Murat.</span>')+
'<div class="hero"><div class="between"><div><div class="k">Bugünkü enerji</div><div class="num">'+format(energy)+' <span class="unit">kcal</span></div><div class="dim">2.100 kcal günlük hedef</div></div><div class="ring" style="--pct:'+Math.min(pct,100)+'%"><b>%'+pct+'</b></div></div><div class="between heroline"><span>Hedefe kalan</span><b>'+format(Math.max(0,2100-energy))+' kcal</b></div></div>'+
hd('Sıradaki öğün',goto('Planım ›','plan','link'))+meal(S.swap?'Seçtiğin öğle alternatifi':'Izgara tavuk tabağı',S.swap?S.swap:'Bulgur pilavı ve mevsim salata')+
'<div class="twins">'+goto('<div class="flex">'+ic('drop')+' Su</div><b>'+format(S.water)+' <small>ml</small></b><small>Bugün içilen su</small>','su','tile')+goto('<div class="flex">'+ic('walk')+' Hareket</div><b>20 <small>dk</small></b><small>'+(S.walkDone?'Tamamlandı':'Açık hava yürüyüşü')+'</small>','hareket','tile walk')+'</div>'+goto(ic('camera')+' Tabağımı analiz et','fotograf','cta')+(S.mealSaved?info('Öğün günlüğüne eklendi',S.savedRange.join('–')+' kcal · kullanıcı onaylı tahmin'):'');
foot=tabnav(id);
}
if(id==='profil'){
html=bar('bugun',steps(1))+'<div class="profilehead">'+ovi+heading('Profil · 1 / 2','Seni <span class="serif">tanıyalım.</span>')+'</div><div class="dim">Günlük planını oluşturmak için bilgilerini gir.</div><div class="panel">'+[['Yaş','age','yıl',18,105],['Boy','height','cm',100,240],['Kilo','weight','kg',30,350]].map(([t,k,u,min,max])=>'<label class="input">'+t+' ('+u+')<input type="number" min="'+min+'" max="'+max+'" step="any" value="'+S[k]+'" onchange="S.'+k+'=Number(this.value)"></label>').join('')+'<label class="input">Cinsiyet<select onchange="S.sex=this.value">'+['Kadın','Erkek','Belirtmek istemiyorum'].map(x=>'<option '+(S.sex===x?'selected':'')+'>'+x+'</option>').join('')+'</select></label></div>'+hd('Günlük hareket düzeyin')+'<div class="seg">'+['Düşük','Orta','Yüksek'].map(x=>act(x,"S.activity='"+x+"';render()",S.activity===x?'on':'')).join('')+'</div>'+(!S.validProfile?info('Bilgilerini kontrol et','Yaş, boy ve kilo için geçerli değerler gir.'):'');
foot=act('Devam et '+ic('next'),"S.validProfile=[...document.querySelectorAll('input')].every(i=>i.value && i.checkValidity());if(S.validProfile){location.hash='hedef'}else{render()}");
}
if(id==='hedef'){html=bar('profil',steps(2))+heading('Profil · 2 / 2','Hedefin <span class="serif">ne?</span>')+'<p class="dim sub">Öğün ve porsiyon önerilerin bu seçime göre şekillenecek.</p><div class="choices">'+goalBtns()+'</div>'+hd('Plan tercihleri')+row('clock','3 ana öğün','Programda öğün saatlerini değiştirebilirsin.')+row('food','Beslenme tercihleri','Üretim akışında alerji ve tercihler burada seçilir.');foot=goto('Günlük planımı gör '+ic('next'),'plan','cta')}
if(id==='plan'){html='<div class="bar">'+word+avatar+'</div>'+heading('20 Kasım · Cuma','Günlük <span class="serif">planım.</span>')+day+
'<div class="between"><b>Beslenme</b><span class="pill">2.100 kcal hedef</span></div><div class="panel">'+row('check','08.30 · Kahvaltı','Peynirli omlet, ekmek ve domates')+row('food','13.00 · Öğle',S.swap||'Izgara tavuk, bulgur ve salata')+row('clock','16.00 · Ara öğün','Meyve ve yoğurt')+row('clock','19.30 · Akşam','Mercimek yemeği ve cacık')+'</div>'+goto(ic('adjust')+' Planım değişti','degistir','cta lime')+hd('Hareket')+linkrow('walk','20 dk yürüyüş',S.walkDone?'Tamamlandı':'Açık hava · rahat tempo','hareket');foot=tabnav(id)}
if(id==='hareket'){html=bar('plan')+heading('Günlük hareket','Yürüyüş <span class="serif">zamanı.</span>')+'<div class="hero"><div class="k">Bugünkü aktivite</div><div class="num">20 <span class="unit">dakika</span></div><svg class="route" viewBox="0 0 300 80" aria-hidden="true"><path d="M10 67 C45 40 72 77 96 47S135 28 152 44 187 67 208 35 258 46 289 13" fill="none" stroke="#d7ed88" stroke-width="5" stroke-linecap="round"/><circle cx="290" cy="13" r="7" fill="#d7ed88"/></svg><div class="dim">Açık hava · rahat tempo</div></div>'+hd('Yürüyüş akışı')+row('clock','Başlangıç','5 dk · yavaş adımlarla başla')+row('walk','Ana bölüm','10 dk · rahat bir tempo seç')+row('leaf','Bitiş','5 dk · temponu yavaşlat');foot=act(ic('check')+' '+(S.walkDone?'Tamamlandı':'Tamamlandı olarak işaretle'),"S.walkDone=true;location.hash='plan'")}
if(id==='fotograf'){html=bar('bugun')+heading('Tabak analizi','Tabağını <span class="serif">göster.</span>')+photo('capture','Örnek fotoğraf')+hd('Fotoğrafını kontrol et')+'<p class="dim">Tabağın tamamı ve yanındaki soslar görünürse porsiyonu kontrol etmek kolaylaşır.</p>'+info('Fotoğraf nerede işleniyor?','Analizi başlattığında yalnızca seçtiğin fotoğraf görsel analiz servisine gönderilir.');foot=goto(ic('camera')+' Örnek tabağı analiz et','analiz','cta')}
if(id==='analiz'){html=bar('fotograf','<span class="pill">Öğle yemeği</span>')+heading('Tabak analizi','Tabağımda <span class="serif">ne var?</span>')+photo('','Örnek analiz')+'<div class="estimate"><strong>'+range()+'</strong><span class="dim">kcal · tahmini</span></div><div class="metricline"><b>Izgara tavuk</b><span>140 g</span></div><div class="metricline"><b>Bulgur pilavı</b><span class="step">'+act('−',"S.rice=Math.max(0,S.rice-25);render()")+S.rice+' g'+act('+',"S.rice=Math.min(500,S.rice+25);render()")+'</span></div><div class="metricline"><b>Mevsim salata</b><span>80 g</span></div><div class="metricline"><span>İlave yağ</span><span class="step">'+act('−',"S.oil=Math.max(0,S.oil-5);render()")+S.oil+' g'+act('+',"S.oil=Math.min(30,S.oil+5);render()")+'</span></div>'+info('Ovi’nin tabak önerisi',S.goal==='Kilo vermek'?'Bulguru 25 g azaltarak tahmini farkı görebilirsin.':S.goal==='Kilo almak'?'Bulguru 25 g artırabilir veya yanına yoğurt ekleyebilirsin.':'Yanına yoğurt eklemek istersen yeni tahmini görebilirsin.')+act(S.added?'Yoğurdu çıkar · 80 g':'Yoğurt ekle · 80 g','S.added=!S.added;render()','link');foot=act(ic('check')+' Günlüğüme kaydet','clickSave()')}
if(id==='degistir'){html=bar('plan')+heading('Öğle yemeği','Planım <span class="serif">değişti.</span>')+'<div class="seg">'+['Dışarıdayım','Evdeyim','Vaktim az'].map(x=>act(x,"S.context='"+x+"';render()",S.context===x?'on':'')).join('')+'</div>'+hd('Öğle alternatifleri')+'<div class="choices">'+({'Dışarıdayım':['Tavuk şiş ve salata','Kuru fasulye ve cacık','Mercimek çorbası ve sandviç'],'Evdeyim':['Sebzeli omlet ve ekmek','Nohut salatası ve yoğurt','Ton balıklı sandviç'],'Vaktim az':['Peynirli tam tahıllı sandviç','Yoğurtlu nohut salatası','Dünden kalan sebze ve bulgur']}[S.context]).map((x,i)=>act('<span class="ico">'+ic('food')+'</span><span>'+x+'</span><span>'+ic('next')+'</span>',"S.swap='"+x+"';location.hash='plan'",'choice')).join('')+'</div><p class="caption">Bir seçeneğe dokunduğunda öğle planına eklenir.</p>';foot=''}
if(id==='su'){
html='<div class="bar">'+word+avatar+'</div>'+heading('Günlük sıvı','Su <span class="serif">takibim.</span>')+
'<div class="wavecard"><div class="k">Bugünkü tüm içecekler</div><div class="num">'+format(total())+' <span class="unit">ml</span></div><div class="hint">'+(S.restricted?'Hekim önerisine göre takip':format(S.target)+' ml hedef · '+format(Math.max(0,S.target-total()))+' ml kaldı')+'</div><svg class="waterart" aria-hidden="true" viewBox="0 0 360 70" preserveAspectRatio="none"><path d="M0 28 Q70 0 160 32 T360 18V70H0" fill="#9ccbd4"/><path d="M0 40 Q100 65 195 35 T360 40V70H0" fill="#6ba6b6"/><path d="M0 56 Q80 32 200 55 T360 50V70H0" fill="#427e8b"/></svg></div>'+
'<div class="metricline"><span>Su</span><b>'+format(S.water)+' ml</b></div><div class="metricline"><span>Diğer içecekler</span><b>'+format(S.other)+' ml</b></div>'+hd('İçecek ekle')+'<div class="seg">'+['Su','Diğer içecek'].map(k=>act(k,"S.drink='"+k+"';render()",S.drink===k?'on':'')).join('')+'</div><div class="twins" style="grid-template-columns:repeat(3,1fr)">'+[150,250,500].map(n=>act(ic('cup')+'<b style="font-size:16px">+ '+n+' ml</b>',"waterAdd("+n+")",'tile')).join('')+'</div>'+(S.waterlog.length?act('Son eklemeyi geri al','waterUndo()','link'):'')+
'<label class="input">Hekim sıvı kısıtlaması önerdi<input style="width:24px;height:20px" type="checkbox" '+(S.restricted?'checked':'')+' onchange="S.restricted=this.checked;render()"></label>'+linkrow('leaf','Ödem rehberi','Ayak ve bacak şişliği için','odem');foot=tabnav(id)}
if(id==='odem'){html=bar('su')+heading('Su ve sıvı','Ödem <span class="serif">rehberi.</span>')+'<div class="panel"><strong>Ne zaman yardım almalıyım?</strong><p class="warn">Şişlikle birlikte nefes darlığı veya göğüs ağrısı varsa Türkiye’de 112’yi ara.</p><p class="hint">Nedeni belirsiz tek taraflı şişlik, aniden başlayan şiddetli şişlik, kızarıklık veya sıcaklık varsa bugün sağlık değerlendirmesi al.</p></div>'+hd('Hafif, iki taraflı şişlikte')+row('walk','Kısa hareket molası','Uygunsa uzun oturma sürelerini hafif yürüyüşle böl.')+row('leaf','Ayaklarını yükselt','Dinlenirken ayaklarını bir yastıkla destekle.')+row('food','Tuzlu eşlikçileri değiştir','Turşu veya çok tuzlu sos yerine taze sebze seçebilirsin.')+'<p class="caption">Şişlik artarsa veya birkaç günde düzelmezse hekime başvur. Sıvı hedefini kendi kendine değiştirme.</p><a class="source mini" href="https://www.nhs.uk/conditions/oedema/">Kaynak · NHS</a>';foot=''}
if(id==='gelisim'){html='<div class="bar">'+word+avatar+'</div>'+heading('16–22 Kasım','Haftalık <span class="serif">gelişim.</span>')+'<div class="hero"><div class="k">Son kilo kaydı</div><div class="num">75,0 <span class="unit">kg</span></div><svg class="graph" viewBox="0 0 320 125" role="img" aria-label="Örnek dört tartım: 75,5; 75,2; 75,3 ve 75 kilogram"><path d="M5 30H315M5 65H315M5 100H315" stroke="#436457" fill="none"/><path d="M8 30 110 71 205 55 312 98" stroke="#d6ef8d" stroke-width="3" fill="none"/>'+[[8,30],[110,71],[205,55],[312,98]].map(([x,y])=>'<circle cx="'+x+'" cy="'+y+'" r="5" fill="#d6ef8d"/>').join('')+'</svg><div class="between mini"><span>16 Kas</span><span>20 Kas</span></div></div>'+hd('Haftanın kayıtları')+row('food','9 öğün','3 farklı günde kaydedildi')+row('walk','40 dakika hareket','2 yürüyüş tamamlandı')+info('Ovi’den haftalık not','İki öğle yemeğini dışarıda seçtin. Yarın için de dışarıda bir alternatif ister misin?')+goto('Öğle alternatiflerini gör','degistir','link');foot=tabnav(id)}
document.getElementById('screen').innerHTML=html;document.getElementById('foot').innerHTML=foot.startsWith('<button')?'<div class="footpad">'+foot+'</div>':foot;if(window.last!==id)document.getElementById('screen').scrollTop=0;window.last=id;document.title='Ovis Fit · '+id}
addEventListener('hashchange',render);render();
