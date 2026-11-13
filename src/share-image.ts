// Adds a small "Made with Family Funnies" strip under a comic before it is
// shared, so the picture carries the app's name wherever it travels. The comic
// itself is untouched. If anything goes wrong the original picture is returned.
const SITE='family-funnies.pages.dev';
export async function withShareFooter(blob:Blob):Promise<Blob>{
 try{
  const picture=await createImageBitmap(blob);
  const w=picture.width,h=picture.height,strip=Math.max(36,Math.round(w*0.042));
  const canvas=document.createElement('canvas');canvas.width=w;canvas.height=h+strip;
  const g=canvas.getContext('2d');if(!g)return blob;
  g.fillStyle='#faf5eb';g.fillRect(0,0,w,h+strip);
  g.drawImage(picture,0,0);picture.close?.();
  g.fillStyle='#42283e';g.textBaseline='middle';
  const size=Math.round(strip*0.44),pad=Math.round(strip*0.5),y=h+strip/2;
  g.font=`700 ${size}px "DM Sans",system-ui,sans-serif`;g.textAlign='left';g.fillText('Made with Family Funnies',pad,y);
  g.font=`500 ${size}px "DM Sans",system-ui,sans-serif`;g.textAlign='right';g.fillText(SITE,w-pad,y);
  const out=await new Promise<Blob|null>(done=>canvas.toBlob(done,'image/jpeg',0.9));
  return out&&out.size>0?out:blob;
 }catch{return blob}
}
