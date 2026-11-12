// Loads every row of a query in pages. The Data API silently caps a single
// response (1,000 rows by default), so one unpaged request can drop rows without
// any error. The exact total from the first response decides when to stop, which
// stays correct even if the server's cap is lower than the page size requested.
export async function fetchAll(fetchPage,{pageSize=1000,maxRows=50000}={}){
 const all=[];let total=Infinity;
 while(all.length<total&&all.length<maxRows){
  const {data,count,error}=await fetchPage(all.length,all.length+pageSize-1);
  if(error)throw error;
  if(typeof count==='number')total=count;
  if(!data?.length)break;
  all.push(...data);
  if(typeof count!=='number'&&data.length<pageSize)break;
 }
 return all;
}
