import {handleBootstrap} from '../../worker/auth-bridge.mjs';
type Env={FIREBASE_PROJECT_ID:string;GOOGLE_SERVICE_ACCOUNT:string};
export const onRequest=(context:{request:Request;env:Env})=>handleBootstrap(context.request,context.env);
