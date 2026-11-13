import {useLayoutEffect,useRef,type TextareaHTMLAttributes} from 'react';
// A textarea that grows to show all of its text, so saved answers are never
// cut off mid-line on a phone. The stylesheet's min-height still applies.
export function AutoTextarea(props:TextareaHTMLAttributes<HTMLTextAreaElement>){
 const ref=useRef<HTMLTextAreaElement>(null);
 const fit=()=>{const el=ref.current;if(!el)return;el.style.height='auto';if(el.scrollHeight>0)el.style.height=el.scrollHeight+(el.offsetHeight-el.clientHeight)+'px'};
 useLayoutEffect(fit);
 return <textarea {...props} ref={ref} onInput={e=>{fit();props.onInput?.(e)}}/>;
}
