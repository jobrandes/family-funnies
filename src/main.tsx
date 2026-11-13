import React, { useEffect, useRef, useState, type FormEvent } from "react";
import { createRoot } from "react-dom/client";
import { AutoTextarea } from "./auto-textarea";
import { withShareFooter } from "./share-image";
import {
  createUserWithEmailAndPassword,
  signInWithEmailAndPassword,
  sendEmailVerification,
  sendPasswordResetEmail,
  onAuthStateChanged,
  signOut,
  type User,
} from "firebase/auth";
import {
  auth,
  db,
  configured,
  rows,
  rpc,
  signedImage,
  firebaseProjectId,
} from "./client";
import "./style.css";
import "./shelves.css";
import {GooglePhotos} from './google-photos';
import {FamilyWizard} from './family-wizard';
import {familyStatus} from './family-status.mjs';
import {pendingInvite,forgetInvite,inviteUrl} from './invite.mjs';
const mirroredFamilies=new Set(['a558ec80-f1ee-4094-9bc2-689d0e54f063','94c3f471-bd68-4390-89fe-74b250b40754','e47f2cc4-c03b-4537-a08a-729c94fe41cf']);
type Row = Record<string, any>;
const errorText = (e: unknown) =>
  e instanceof Error
    ? e.message
    : typeof e === "object" && e && "message" in e
      ? String(e.message)
      : "Something went wrong. Please try again.";
const readInvite = (): string | null => pendingInvite(location.hash, localStorage);
// Carry a pending invitation through the verification email. Firebase rejects
// continue links it does not accept, so fall back to the plain address.
async function sendVerification(user: User) {
  try {
    await sendEmailVerification(user, { url: inviteUrl(location.origin, readInvite()) });
  } catch (e) {
    if ((e as { code?: string })?.code !== "auth/invalid-continue-uri") throw e;
    await sendEmailVerification(user, { url: location.origin });
  }
}
function App() {
  const [user, setUser] = useState<User | null>(null),
    [loading, setLoading] = useState(true),
    [families, setFamilies] = useState<Row[]>([]),
    [familyId, setFamilyId] = useState<string | null>(null),
    [tab, setTab] = useState("Comics"),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false),
    [newFamily, setNewFamily] = useState(false);
  const [memberships, setMemberships] = useState<Row[]>([]);
  const [wizardId,setWizardId]=useState<string|null>(null);
  const [collectionLoading,setCollectionLoading]=useState(true);
  const [invite,setInvite]=useState<string|null>(readInvite);
  useEffect(()=>{const changed=()=>setInvite(readInvite());window.addEventListener('hashchange',changed);return()=>window.removeEventListener('hashchange',changed)},[]);
  // Families that list this account's verified email on a cast member.
  const [matches,setMatches]=useState<Row[]>([]),[skipped,setSkipped]=useState<string[]>([]),[joined,setJoined]=useState('');
  async function loadMatches(){
    const uid=auth?.currentUser?.uid;if(!uid)return;
    try{const offers=await rpc('my_family_matches',{});if(auth?.currentUser?.uid===uid)setMatches(offers)}
    catch{if(auth?.currentUser?.uid===uid)setMatches([])/* not switched on, or offline: nothing to offer */}
  }
  useEffect(()=>{setMatches([]);setSkipped([]);setJoined('');if(user?.emailVerified)void loadMatches()},[user]);
  const dropInvite=()=>{forgetInvite(localStorage);if(location.hash.includes('invite='))history.replaceState(null,'',location.pathname);setInvite(null)};
  useEffect(() => {
    if (!auth) {
      setLoading(false);
      return;
    }
    return onAuthStateChanged(auth, (u) => {
      setUser(u);
      setLoading(false);
      if (!u) {
        setFamilies([]);
        setFamilyId(null);
        setMemberships([]);
      }
    });
  }, []);
  async function refresh() {
    try {
      setError("");
      // Readers cannot read the family record (it holds private notes); the
      // server hands them just the name and status for their shelf.
      const [f, m, r] = await Promise.all([
        rows("families"),
        rows("family_memberships"),
        rpc("reader_families", {}).catch(() => [] as Row[]),
      ]);
      setFamilies([...f, ...(r as Row[]).filter((x) => !f.some((y) => y.id === x.id))]);
      setMemberships(m);
    } catch (e) {
      setError(errorText(e));
    } finally {
      setCollectionLoading(false);
    }
  }
  useEffect(() => {
    if (user?.emailVerified) {setCollectionLoading(true);void refresh();}
  }, [user]);
  const family = families.find((f) => f.id === familyId);
  const actor = user
    ? `https://securetoken.google.com/${firebaseProjectId}|${user.uid}`
    : "";
  const role = memberships.find(
    (m) => m.family_id === familyId && m.actor_id === actor,
  )?.role;
  async function act(fn: () => Promise<void>) {
    setBusy(true);
    setError("");
    try {
      await fn();
    } catch (e) {
      setError(errorText(e));
    } finally {
      setBusy(false);
    }
  }
  return (
    <>
      <header>
        <a
          className="brand"
          href="/"
          onClick={(e) => {
            e.preventDefault();
            setFamilyId(null);
          }}
        >
          <span aria-hidden="true">▤</span> Our Family Funnies
        </a>
        {user && (
          <button className="quiet" onClick={() => void signOut(auth!)}>
            Sign out
          </button>
        )}
      </header>
      <main>
        {error && (
          <div className="notice error" role="alert">
            {error}
            <div>
              {user?.emailVerified && (
                <button
                  className="quiet"
                  disabled={busy}
                  onClick={() => void act(refresh)}
                >
                  Refresh
                </button>
              )}
              <button
                className="quiet"
                onClick={() => setError("")}
                aria-label="Dismiss error"
              >
                ×
              </button>
            </div>
          </div>
        )}
        {loading ? (
          <p role="status">Opening your collection…</p>
        ) : !configured ? (
          <section className="welcome">
            <p className="eyebrow">A new home for your family stories</p>
            <h1>
              Every family has
              <br />a funny side.
            </h1>
            <p>
              Your private comic bookshelf is taking shape. Account setup is
              still being connected; this version is not open for sign-ups yet.
            </p>
            <div className="paper">
              <strong>Your existing comics are safe.</strong>
              <p>
                Keep using your current family links while we finish connecting
                this new app.
              </p>
            </div>
          </section>
        ) : !user ? (
          <Login busy={busy} run={act} invited={!!invite} />
        ) : !user.emailVerified ? (
          <VerifyEmail user={user} onVerified={(verified)=>setUser(Object.assign(Object.create(Object.getPrototypeOf(verified)),verified))}/>
        ) : collectionLoading ? <section className="paper narrow" role="status"><p className="eyebrow">Email verified</p><h1>Opening your families…</h1><p>Your account is ready.</p></section> : (
          <>
            {!family && joined && (
              <div className="notice success" role="status">
                You joined <strong>{joined}</strong>. Its comics are on your shelf.
              </div>
            )}
            {!family && matches.filter((x) => !skipped.includes(x.match_id)).map((x) => (
              <section className="paper invite match-offer" key={x.match_id} aria-label={"Invitation to " + x.family_name}>
                <p className="eyebrow">You’re in a family</p>
                <h2>{x.family_name} has you in its cast as “{x.cast_name}”.</h2>
                <p>
                  Want to join? You’ll be able to read this family’s comics. You
                  won’t be able to change anything.
                </p>
                <p className="small muted">Matched to your verified email, {user.email}.</p>
                <div className="actions">
                  <button
                    disabled={busy}
                    onClick={() =>
                      void act(async () => {
                        try {
                          await rpc("accept_family_match", { target_match: x.match_id });
                        } finally {
                          await loadMatches();
                        }
                        setJoined(x.family_name);
                        await refresh();
                      })
                    }
                  >
                    Join as a reader
                  </button>
                  <button className="secondary" disabled={busy} onClick={() => setSkipped((s) => [...s, x.match_id])}>
                    Not now
                  </button>
                  <button
                    className="quiet"
                    disabled={busy}
                    onClick={() =>
                      void act(async () => {
                        await rpc("decline_family_match", { target_match: x.match_id });
                        await loadMatches();
                      })
                    }
                  >
                    This isn’t me. Don’t ask again
                  </button>
                </div>
              </section>
            ))}
            {invite && (
              <section className="paper invite">
                <h2>You have a family invitation.</h2>
                <p>Join to add this family to your bookshelf.</p>
                <div className="actions">
                <button
                  disabled={busy}
                  onClick={() =>
                    void act(async () => {
                      let id: string;
                      try {
                        id = await rpc("accept_invitation", { token: invite });
                      } catch (e) {
                        // Used, expired, revoked or already joined: it can never
                        // succeed later, so stop offering it.
                        if (/Invitation unavailable|already belong/.test(errorText(e))) dropInvite();
                        throw e;
                      }
                      dropInvite();
                      await refresh();
                      setFamilyId(id);
                    })
                  }
                >
                  Accept invitation
                </button>
                <button className="quiet" disabled={busy} onClick={dropInvite}>
                  Not now
                </button>
                </div>
              </section>
            )}
            {!family ? (
              <>
                <section className="shelves-welcome">
                  <p className="eyebrow">Your own little comic collection</p>
                  <h1>
                    All your families.
                    <br />
                    <i>All their funny sides.</i>
                  </h1>
                  <p>
                    Different circles. Familiar faces. Each family has its own
                    personality.
                  </p>
                </section>
                <FamilyShelves
                  families={families}
                  memberships={memberships}
                  actor={actor}
                  open={(id, section) => {
                    setFamilyId(id);
                    setTab(section);
                  }}
                  onError={setError}
                  resume={(id)=>{setWizardId(id);setNewFamily(true)}}
                />
                <FamilyTrash run={act} busy={busy} onChange={refresh}/>
                {!!families.length && (
                  <div className="shelf-create">
                    <button
                      className="secondary"
                      onClick={() => setNewFamily(true)}
                    >
                      ＋ Create a family
                    </button>
                    <p>
                      Different circles. Familiar faces. Each family gets its
                      own funny pages.
                    </p>
                  </div>
                )}
                {!families.length && !error && (
                  <section className="empty paper">
                    <span className="illustration" aria-hidden="true">
                      ▤
                    </span>
                    <h2>Your first shelf starts here.</h2>
                    <p>
                      Create a family, or accept a family invitation to join
                      their collection.
                    </p>
                    <button onClick={() => setNewFamily(true)}>
                      Create your first family
                    </button>
                  </section>
                )}
              </>
            ) : (
              <>
                <button
                  className="quiet back"
                  onClick={() => setFamilyId(null)}
                >
                  ← My families
                </button>
                <section className="page-heading">
                  <div>
                    <p className="eyebrow">Your family edition</p>
                    <h1>{family.name}</h1>
                  </div>
                  <span className="badge">
                    {role === "owner"
                      ? "Family manager"
                      : role === "contributor"
                        ? "Contributor"
                        : "Reader"}
                  </span>
                </section>
                <nav className="tabs" aria-label="Family sections">
                  {(role === "reader"
                    ? ["Comics"]
                    : [
                        "Comics",
                        "People & pets",
                        "Story jar",
                        "Cast",
                        ...(role === "owner" ? ["Settings"] : []),
                      ]
                  ).map((t) => (
                    <button
                      key={t}
                      className={tab === t ? "active" : ""}
                      aria-current={tab === t ? "page" : undefined}
                      onClick={(e) => {
                        // Slide the chosen tab into view sideways only; never move the page.
                        const b = e.currentTarget, n = b.parentElement!;
                        const left = b.getBoundingClientRect().left - n.getBoundingClientRect().left + n.scrollLeft;
                        n.scrollTo({ left: left - (n.clientWidth - b.offsetWidth) / 2, behavior: "smooth" });
                        setTab(t);
                      }}
                    >
                      {t}
                    </button>
                  ))}
                </nav>
                {role==='owner'&&family.onboarding_step>0&&family.onboarding_step<5&&<div className="setup-resume"><span>Your family setup is saved. Continue where you left off.</span><button onClick={()=>{setWizardId(family.id);setNewFamily(true)}}>Continue setup →</button></div>}
                {tab === "Comics" && (
                  <Comics id={family.id} onError={setError} />
                )}
                {tab === "People & pets" && (
                  <People
                    id={family.id}
                    run={act}
                    busy={busy}
                    onChange={refresh}
                    owner={role==='owner'}
                  />
                )}
                {tab === "Story jar" && (
                  <StoryJar id={family.id} run={act} busy={busy} />
                )}
                {tab === "Cast" && (
                  <Cast
                    onChange={refresh}
                    family={family}
                    owner={role === "owner"}
                    run={act}
                    busy={busy}
                  />
                )}
                {tab === "Settings" && role === "owner" && (
                  <Settings
                    family={family}
                    run={act}
                    busy={busy}
                    onChange={refresh}
                  />
                )}
              </>
            )}
          </>
        )}
      </main>
      {newFamily&&user?.emailVerified&&<FamilyWizard initialId={wizardId} onClose={()=>{setNewFamily(false);setWizardId(null)}} onChanged={refresh} onComplete={(id)=>{setNewFamily(false);setWizardId(null);setFamilyId(id);setTab('Cast')}} renderPeople={(id,stage,tools)=><People id={id} stage={stage} owner run={tools.run} busy={tools.busy} onChange={tools.refresh}/>}/>}
      <footer>
        Little stories. A lot of love.
        <span><a href="/privacy.html">Privacy policy</a> · <a href="/terms.html">Terms of service</a></span>
        <span>Fictional, affectionate family comedy.</span>
      </footer>
    </>
  );
}
function FamilyShelves({
  families,
  memberships,
  actor,
  open,
  onError,
  resume,
}: {
  families: Row[];
  memberships: Row[];
  actor: string;
  open: (id: string, section: string) => void;
  onError: (message: string) => void;
  resume:(id:string)=>void;
}) {
  const [details, setDetails] = useState<{
    people: Row[];
    casts: Row[];
    episodes: Row[];
    jobs:Row[];
  } | null>(null);
  useEffect(() => {
    let active = true;
    setDetails(null);
    if (!families.length) return;
    Promise.all([rows("people"), rows("cast_versions"), rows("episodes", undefined, EPISODE_LIST),rows('cast_jobs')])
      .then(([people, casts, episodes,jobs]) => {
        if (active) setDetails({ people, casts, episodes,jobs });
      })
      .catch((e) => {
        if (active) onError(errorText(e));
      });
    return () => {
      active = false;
    };
  }, [families]);
  const today = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Los_Angeles",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
  return (
    <section className="shelves-grid" aria-label="Your families">
      {families.map((f) => {
        const people =
          details?.people.filter((p) => p.family_id === f.id) ?? [];
        const cast = details?.casts
          .filter((c) => c.family_id === f.id)
          .sort((a, b) => b.created_at.localeCompare(a.created_at))[0];
        const latest = details?.episodes
          .filter((e) => e.family_id === f.id)
          .sort((a, b) => b.day.localeCompare(a.day))[0];
        const role = memberships.find(
          (m) => m.family_id === f.id && m.actor_id === actor,
        )?.role;
        const job=details?.jobs.find(j=>j.family_id===f.id&&j.visual_revision===f.visual_revision);
        return (
          <article className="family-shelf" key={f.id}>
            <button
              className="shelf-art"
              onClick={() => open(f.id, "Comics")}
              aria-label={"Open " + f.name + " comics"}
            >
              {cast?.object_path ? (
                <PrivateImage
                  bucket="family-comics"
                  path={cast.object_path}
                  alt={f.name + " cast"}
                />
              ) : (
                <span className="shelf-art-placeholder">
                  <span aria-hidden="true">▤</span>
                  {details
                    ? "Your cast is taking shape"
                    : "Opening your family…"}
                </span>
              )}
            </button>
            <div className="shelf-card-body">
              <h2>{f.name}</h2>
              <p className="shelf-members">
                {people.map((p) => p.name.trim()).join(", ") ||
                  "Your family edition"}
              </p>
              <span
                className={
                  "shelf-badge " + (latest?.day === today ? "new" : "")
                }
              >
                {!details?"Opening collection…":familyStatus(f,cast,job,latest,today,role)}
              </span>
              <p className="shelf-latest">
                {latest ? (
                  <>
                    Latest comic: <strong>{latest.title}</strong>
                  </>
                ) : (
                  "Your funny pages start here."
                )}
              </p>
              <button onClick={() => open(f.id, "Comics")}>
                Read comics →
              </button>
              {role==='owner'&&f.onboarding_step>0&&f.onboarding_step<5&&<button className="secondary" onClick={()=>resume(f.id)}>Continue setup →</button>}
              {role && role !== "reader" && (
                <button
                  className="secondary"
                  onClick={() => open(f.id, "People & pets")}
                >
                  Manage family
                </button>
              )}
            </div>
          </article>
        );
      })}
    </section>
  );
}
function VerifyEmail({user,onVerified}:{user:User;onVerified:(user:User)=>void}){
 const [message,setMessage]=useState(''),[error,setError]=useState(''),[sending,setSending]=useState(false),[checking,setChecking]=useState(false);
 const [lastSent,setLastSent]=useState(()=>Number(sessionStorage.getItem('verification-sent:'+user.uid)||0));
 const [now,setNow]=useState(Date.now());
 const inFlight=useRef(false);
 const remaining=Math.max(0,Math.ceil((lastSent+60000-now)/1000));
 async function check(manual=false){
  if(inFlight.current||document.visibilityState==='hidden')return;
  inFlight.current=true;if(manual){setChecking(true);setError('');}
  try{
   await user.reload();const current=auth?.currentUser;
   if(current?.emailVerified){await current.getIdToken(true);onVerified(current);}
   else if(manual)setMessage('Still waiting for the email link to be opened. We’ll keep checking automatically.');
  }catch{if(manual)setError('Could not check your email yet. Check your connection and try again.');}
  finally{inFlight.current=false;if(manual)setChecking(false);}
 }
 useEffect(()=>{
  const poll=setInterval(()=>void check(),5000),clock=setInterval(()=>setNow(Date.now()),1000);
  const focus=()=>void check();window.addEventListener('focus',focus);document.addEventListener('visibilitychange',focus);
  void check();
  return()=>{clearInterval(poll);clearInterval(clock);window.removeEventListener('focus',focus);document.removeEventListener('visibilitychange',focus);};
 },[user]);
 async function resend(){
  if(sending||remaining)return;setSending(true);setError('');
  try{await sendVerification(user);const sent=Date.now();sessionStorage.setItem('verification-sent:'+user.uid,String(sent));setLastSent(sent);setNow(sent);setMessage('A new verification email was requested. Use the newest email link.');}
  catch(e){setError(errorText(e));}finally{setSending(false);}
 }
 return <section className="narrow paper"><p className="eyebrow">One quick check</p><h1>Check your email.</h1><p>Open the verification link sent to <strong>{user.email}</strong>.</p><div className="notice"><strong>Then you’re ready.</strong><p>This page checks automatically and opens your families after verification. There’s no separate activation wait.</p></div><p className="muted">Email can take a few minutes. Check Spam or Junk and search for “Family Funnies.” Use the newest verification email if you request another.</p>{message&&<p role="status">{message}</p>}{error&&<p role="alert">{error}</p>}<div className="actions"><button disabled={checking} onClick={()=>void check(true)}>{checking?'Checking…':'I’ve verified my email'}</button><button className="quiet" disabled={sending||remaining>0} onClick={()=>void resend()}>{sending?'Sending…':remaining?`Resend in ${remaining}s`:'Resend verification email'}</button></div><p className="small muted">Wrong email? <button className="quiet" onClick={()=>void signOut(auth!)}>Sign out and use another address</button></p></section>;
}
function Login({
  run,
  busy,
  invited,
}: {
  run: (fn: () => Promise<void>) => Promise<void>;
  busy: boolean;
  invited: boolean;
}) {
  const [mode, setMode] = useState("signin"),
    [message, setMessage] = useState(""),
    [sentAt,setSentAt]=useState(0),[clock,setClock]=useState(Date.now());
  const retryIn=Math.max(0,Math.ceil((sentAt+60000-clock)/1000));
  useEffect(()=>{if(!sentAt)return;const timer=setInterval(()=>setClock(Date.now()),1000);return()=>clearInterval(timer)},[sentAt]);
  async function submit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const d = new FormData(e.currentTarget);
    await run(async () => {
      const email = String(d.get("email"));
      if (mode === "reset") {
        if(retryIn)return;
        await sendPasswordResetEmail(auth!, email,{url:location.origin});
        setSentAt(Date.now());setClock(Date.now());
        setMessage(
          "Reset email requested. If that address has an account, look for the email from Family Funnies. Check Spam or Junk too. Delivery can take a few minutes; use the newest reset email.",
        );
        return;
      }
      const password = String(d.get("password"));
      if (mode === "signup") {
        const result = await createUserWithEmailAndPassword(
          auth!,
          email,
          password,
        );
        sessionStorage.setItem('verification-sent:'+result.user.uid,String(Date.now()));
        await sendVerification(result.user);
      } else await signInWithEmailAndPassword(auth!, email, password);
    });
  }
  const formRef = useRef<HTMLFormElement>(null);
  function toForm(next: "signup" | "signin") {
    setMode(next);
    setMessage("");
    const form = formRef.current;
    if (!form) return;
    const calm = matchMedia("(prefers-reduced-motion: reduce)").matches;
    form.scrollIntoView({ behavior: calm ? "auto" : "smooth", block: "start" });
    form.querySelector<HTMLInputElement>('input[name="email"]')?.focus({ preventScroll: true });
  }
  return (
    <section className={"login-layout home"+(invited?" invited":"")}>
      <div className="home-pitch">
        <p className="eyebrow">Made for your people</p>
        <h1>
          Your family.
          <br />
          Your funny pages.
        </h1>
        <p className="home-lede">
          A new comic every morning, starring the people and pets you love.
          Drawn by AI from the photos and little stories you share.
        </p>
        <SampleComic />
        <div className="home-actions">
          <button type="button" onClick={() => toForm("signup")}>Start your family</button>
          <button type="button" className="secondary" onClick={() => toForm("signin")}>Sign in</button>
        </div>
        <h2 className="home-steps-title">How it works</h2>
        <ol className="home-steps">
          <li>
            <strong>Add your people.</strong> Names, a photo or two, and what
            makes them who they are. Pets count.
          </li>
          <li>
            <strong>Approve the cast.</strong> Everyone’s cartoon look is ready
            the next morning. Nothing runs until you say yes.
          </li>
          <li>
            <strong>Wake up to a comic.</strong> A fresh one each morning after
            that, for your family to read and share.
          </li>
        </ol>
        <p className="home-privacy">
          <strong>Private to your family.</strong> You choose who is invited.
          Your photos and stories are never sold and never used for ads.{" "}
          <a href="/privacy.html">How we handle them</a>
        </p>
        <p className="muted">
          Invited to read a family’s comics? Open your invitation link, then
          sign in or create an account.
        </p>
      </div>
      <form className="paper" id="account" ref={formRef} onSubmit={submit}>
        <h2>
          {mode === "signup"
            ? "Start your collection"
            : mode === "reset"
              ? "Reset your password"
              : "Sign in"}
        </h2>
        {invited && (
          <div className="notice">
            <strong>You have a family invitation.</strong>
            <p>Sign in or create an account and it will be waiting for you.</p>
          </div>
        )}
        {message && <p role="status">{message}</p>}
        <label>
          Email
          <input name="email" type="email" autoComplete="email" required />
        </label>
        {mode !== "reset" && (
          <label>
            Password
            <input
              name="password"
              type="password"
              autoComplete={
                mode === "signup" ? "new-password" : "current-password"
              }
              minLength={8}
              required
            />
          </label>
        )}
        <button disabled={busy||(mode==='reset'&&retryIn>0)}>
          {busy
            ? "One moment…"
            : mode === "signup"
              ? "Create account"
              : mode === "reset"
                ? retryIn?`Request another in ${retryIn}s`:sentAt?'Request another reset email':"Send reset email"
                : "Sign in"}
        </button>
        {mode==='reset'&&<button type="button" className="quiet" onClick={()=>{setMode('signin');setMessage('')}}>Back to sign in</button>}
        <button
          type="button"
          className="quiet"
          onClick={() => {
            setMode(mode === "signup" ? "signin" : "signup");
            setMessage("");
          }}
        >
          {mode === "signup"
            ? "Already have an account? Sign in"
            : "New here? Create an account"}
        </button>
        {mode === "signin" && (
          <button
            type="button"
            className="quiet"
            onClick={() => setMode("reset")}
          >
            Forgot password?
          </button>
        )}
      </form>
    </section>
  );
}
// Lists never show the script, so do not download it with every row.
const EPISODE_LIST = "id,family_id,day,title,object_path";
function useRows(table: string, id: string, columns?: string) {
  const [data, setData] = useState<Row[]>([]),
    [error, setError] = useState(""),
    [loading, setLoading] = useState(true);
  async function refresh() {
    setLoading(true);
    try {
      setData(await rows(table, id, columns));
      setError("");
    } catch (e) {
      setError(errorText(e));
    } finally {
      setLoading(false);
    }
  }
  useEffect(() => {
    void refresh();
  }, [table, id, columns]);
  return { data, error, loading, refresh };
}
// The sample comic is a picture of an invented family. It appears only once
// public/sample-comic.webp exists, so the page never shows a broken image.
function SampleComic() {
  const [state, setState] = useState<"loading" | "ready" | "missing">("loading");
  if (state === "missing") return null;
  return (
    <figure className="home-sample" hidden={state !== "ready"}>
      <img
        src="/sample-comic.webp"
        width={1200}
        height={800}
        alt="Sample three-panel comic. A mum and daughter decide to teach the family dog to put his toys away. The dog drops a ball in Dad’s hand. In the end the humans tidy the toys while the dog lounges on the sofa, and Mum says he has trained the whole family."
        onLoad={() => setState("ready")}
        onError={() => setState("missing")}
      />
      <figcaption>A sample family we made up. Yours will star your people.</figcaption>
    </figure>
  );
}
function PrivateImage({
  bucket,
  path,
  alt,
  compact,
}: {
  bucket: string;
  path: string;
  alt: string;
  compact?: boolean;
}) {
  const [src, setSrc] = useState(""),
    [error, setError] = useState(false);
  useEffect(() => {
    let active = true;
    setSrc("");
    setError(false);
    signedImage(bucket, path)
      .then((s) => {
        if (active) setSrc(s);
      })
      .catch(() => {
        if (active) setError(true);
      });
    return () => {
      active = false;
    };
  }, [bucket, path]);
  if (compact)
    return src ? (
      <img className="thumb" src={src} alt={alt} loading="lazy" />
    ) : (
      <span className="thumb" role="img" aria-label={error ? "Photo unavailable" : "Opening photo"} />
    );
  return error ? (
    <p>Image unavailable. Reopen this page to try again.</p>
  ) : src ? (
    <img src={src} alt={alt} />
  ) : (
    <p role="status">Opening image…</p>
  );
}
function Comics({ id, onError }: { id: string; onError: (s: string) => void }) {
  const { data, error, loading } = useRows("episodes", id, EPISODE_LIST),
    [selected, setSelected] = useState("");
  useEffect(() => {
    if (error) onError(error);
  }, [error]);
  const comics = [...data].sort((a, b) => b.day.localeCompare(a.day));
  const comic = comics.find((c) => c.id === selected) ?? comics[0];
  // Sharing hands the finished picture to the phone's share sheet, or saves it
  // where sharing files is not supported. Some browsers only allow the share
  // sheet directly from a tap, so a prepared file is kept for a second tap.
  const [sharing, setSharing] = useState(false),
    [prepared, setPrepared] = useState<{ id: string; file: File } | null>(null),
    [shareNote, setShareNote] = useState("");
  useEffect(() => { setShareNote(""); }, [comic?.id]);
  async function shareComic(c: Row) {
    setShareNote("");
    try {
      let file = prepared && prepared.id === c.id ? prepared.file : null;
      if (!file) {
        setSharing(true);
        const signed = await db!.storage.from("family-comics").createSignedUrl(c.object_path, 60);
        if (signed.error) throw signed.error;
        const response = await fetch(signed.data.signedUrl);
        if (!response.ok) throw new Error("This comic could not be prepared for sharing. Please try again.");
        const blob = await withShareFooter(await response.blob());
        const type = /^image\/(png|jpeg|webp)$/.test(blob.type) ? blob.type : "image/png";
        const name = (String(c.title).replace(/[^\p{L}\p{N} _-]+/gu, "").trim().slice(0, 60) || "Family comic") + " " + c.day + "." + type.slice(6).replace("jpeg", "jpg");
        file = new File([blob], name, { type });
        setPrepared({ id: c.id, file });
      }
      if (navigator.canShare?.({ files: [file] })) {
        try {
          await navigator.share({ files: [file], title: String(c.title) });
        } catch (e) {
          const kind = (e as { name?: string })?.name;
          if (kind === "NotAllowedError") setShareNote("Ready. Tap Share comic once more.");
          else if (kind !== "AbortError") throw e;
        }
        return;
      }
      const url = URL.createObjectURL(file), link = document.createElement("a");
      link.href = url; link.download = file.name; link.click();
      setTimeout(() => URL.revokeObjectURL(url), 2000);
      setShareNote("Saved to this device so you can send it.");
    } catch (e) {
      onError(errorText(e));
    } finally {
      setSharing(false);
    }
  }
  return loading ? (
    <p role="status">Opening comics…</p>
  ) : comic ? (
    <div className="comic-layout">
      <article className="paper comic">
        <div className="comic-heading">
          <p className="eyebrow">{comic.day}</p>
          <h2>{comic.title}</h2>
        </div>
        <PrivateImage
          bucket="family-comics"
          path={comic.object_path}
          alt={comic.title}
        />
        <div className="comic-actions">
          <button className="secondary" disabled={sharing} onClick={() => void shareComic(comic)}>
            {sharing ? "Preparing…" : "Share comic"}
          </button>
          {shareNote && <span className="small muted" role="status">{shareNote}</span>}
        </div>
      </article>
      <aside className="paper">
        <p className="eyebrow">The collection</p>
        <h2>Your comic archive</h2>
        {comics.map((c) => (
          <button
            key={c.id}
            className={"archive-item " + (c.id === comic.id ? "selected" : "")}
            onClick={() => setSelected(c.id)}
          >
            {c.title}
            <small>{c.day}</small>
          </button>
        ))}
      </aside>
    </div>
  ) : (
    <section className="empty paper">
      <h2>Your first funny page is still to come.</h2>
      <p>
        Add your people and photos, approve your cast, and turn on daily comics.
        New episodes appear here after morning generation finishes.
      </p>
    </section>
  );
}
type Runner = {
  run: (fn: () => Promise<void>) => Promise<void>;
  busy: boolean;
};
function People({
  id,
  run,
  busy,
  onChange,
  stage,
  owner=false,
}: { id: string; onChange: () => Promise<void>;stage?:'members'|'photos';owner?:boolean } & Runner) {
  const { data, error, refresh } = useRows("people", id),
    photos = useRows("reference_photos", id),
    [editing, setEditing] = useState<Row | null>(null);
  const [removing,setRemoving]=useState<string|null>(null),[confirmation,setConfirmation]=useState('');
  // Quietly retry cleanup of stored photos that no profile uses any more (an
  // earlier removal that lost its connection). Never blocks or alarms the page.
  useEffect(()=>{
    if(stage)return;
    void (async()=>{
      try{
        const stale:Row[]=await rpc('orphan_reference_files',{fid:id});
        const paths=stale.map(x=>x.path).filter(p=>typeof p==='string'&&p.startsWith(id+'/'));
        if(paths.length)await db!.storage.from('family-references').remove(paths.slice(0,100));
      }catch{/* best effort; retried on the next visit */}
    })();
  },[id,stage]);
  // Owner-only: emails attached to cast members, keyed by person. `null` means
  // the feature is not available here (not the owner, or not switched on yet).
  const [emails,setEmails]=useState<Record<string,Row>|null>(null);
  async function loadEmails(){
    if(!owner){setEmails(null);return;}
    try{const list:Row[]=await rpc('list_member_emails',{fid:id});setEmails(Object.fromEntries(list.map(x=>[x.person_id,x])))}
    catch{setEmails(null)}
  }
  useEffect(()=>{void loadEmails()},[id,owner]);
  async function saved() {
    await refresh();
    await photos.refresh();
    await loadEmails();
    await onChange();
  }
  return (
    <>
      <div className="section-heading">
        <div>
          {stage!=='members'&&<h2>{stage==='photos'?'A reference for everyone':'The people behind the punchlines'}</h2>}
          <p>
            Start with a photo and a few details. You can add the rest later.
          </p>
        </div>
        {stage!=='photos'&&<button onClick={() => setEditing({})}>＋ Add person or pet</button>}
      </div>
      {error && <p role="alert">{error}</p>}
      {editing && (
        <form
          className="paper editor"
          onSubmit={(e) => {
            e.preventDefault();
            const f = e.currentTarget,
              d = new FormData(f);
            void run(async () => {
              const value = {
                family_id: id,
                name: String(d.get("name")),
                kind: String(d.get("kind")),
                relationship: String(d.get("relationship")),
                appearance: d.has('appearance')?String(d.get("appearance")):editing.appearance||'',
                personality: d.has('personality')?String(d.get("personality")):editing.personality||'',
                habits: d.has('habits')?String(d.get("habits")):editing.habits||'',
                interests: d.has('interests')?String(d.get("interests")):editing.interests||'',
                boundaries: d.has('boundaries')?String(d.get("boundaries")):editing.boundaries||'',
                memorial: d.get("memorial") === "on",
                memorial_caption: String(d.get("memorial_caption")),
              };
              const result = editing.id
                ? await db!
                    .from("people")
                    .update(value)
                    .eq("id", editing.id)
                    .select("id")
                    .single()
                : await db!.from("people").insert(value).select("id").single();
              if (result.error) throw result.error;
              if (emails && d.has("match_email")) {
                const wanted = value.kind === "person" ? String(d.get("match_email")).trim().toLowerCase() : "";
                if (wanted !== (emails[result.data.id]?.email ?? "")) {
                  try {
                    await rpc("set_member_email", { target_person: result.data.id, new_email: wanted });
                  } catch (e) {
                    // The profile itself is saved; keep the form open on the email problem.
                    await saved();
                    setEditing({ ...editing, ...value, id: result.data.id });
                    throw e;
                  }
                }
              }
              setEditing(null);
              await saved();
            });
          }}
        >
          <h2>
            {editing.id ? "Edit " + editing.name : "Meet a new cast member"}
          </h2>
          <div className="form-grid">
            <label>
              Name
              <input
                name="name"
                defaultValue={editing.name}
                required
                maxLength={100}
              />
            </label>
            <label>
              Cast member
              <select name="kind" defaultValue={editing.kind ?? "person"}>
                <option value="person">Person</option>
                <option value="pet">Pet</option>
              </select>
            </label>
            <label>
              Relationship
              <input
                name="relationship"
                defaultValue={editing.relationship}
                placeholder="Mom, grandpa, family dog…"
              />
            </label>
            {stage!=='members'&&<><label>
              Appearance & clothes
              <AutoTextarea
                name="appearance"
                defaultValue={editing.appearance}
                placeholder="Favorite outfit, hairstyle, one upright ear…"
              />
            </label>
            <label>
              What are they like?
              <AutoTextarea
                name="personality"
                defaultValue={editing.personality}
                placeholder="The planner? The quiet comedian?"
              />
            </label>
            <label>
              Habits & favorite sayings
              <AutoTextarea
                name="habits"
                defaultValue={editing.habits}
                placeholder="What does everyone recognize about them?"
              />
            </label>
            <label>
              Things they enjoy
              <AutoTextarea name="interests" defaultValue={editing.interests} />
            </label>
            <label>
              Keep out of the jokes
              <AutoTextarea name="boundaries" defaultValue={editing.boundaries} />
            </label></>}
          </div>
          {emails && (
            <fieldset className="member-match">
              <legend>Let {editing.name || "them"} read this family’s comics</legend>
              <p className="small">
                Add the email they sign in with. Next time they open the app,
                they’ll be asked if they want to join.
              </p>
              <label>
                Their email <span className="muted">Optional</span>
                <input
                  name="match_email"
                  type="email"
                  inputMode="email"
                  autoComplete="off"
                  autoCapitalize="none"
                  spellCheck={false}
                  maxLength={254}
                  defaultValue={editing.id ? emails[editing.id]?.email ?? "" : ""}
                  placeholder="name@example.com"
                />
              </label>
              <p className="small">
                <strong>Joins as:</strong> Reader · comics only
                {editing.id && emails[editing.id] && (
                  <> · {emails[editing.id].status === "joined" ? "Has joined" : "Waiting for them to sign in"}</>
                )}
              </p>
              <ul className="small muted">
                <li>We don’t email them. Let them know to look for it.</li>
                <li>They only see this family, none of your others.</li>
                <li>They must accept before anything is shared.</li>
                <li>Clearing the email stops the offer. It doesn’t remove someone who already joined.</li>
              </ul>
            </fieldset>
          )}
          <label className="checkbox">
            <input
              name="memorial"
              type="checkbox"
              defaultChecked={editing.memorial}
            />
            Remembered with love — has passed away
          </label>
          <p className="muted">
            Remembered family members appear in a portrait or memory, rather
            than physically in present-day scenes.
          </p>
          <label>
            Remembrance caption
            <input
              name="memorial_caption"
              defaultValue={editing.memorial_caption}
              placeholder="Always with us"
            />
          </label>
          <div className="actions">
            <button disabled={busy}>Save cast member</button>
            <button
              type="button"
              className="quiet"
              onClick={() => setEditing(null)}
            >
              Cancel
            </button>
          </div>
        </form>
      )}
      <div className="people-grid">
        {data.map((p) => {
          const refs = photos.data
            .filter((r) => r.person_id === p.id)
            .sort((a, b) => a.position - b.position);
          return (
            <article className="paper person" key={p.id}>
              {refs[0] && (
                <PrivateImage
                  bucket="family-references"
                  path={refs[0].object_path}
                  alt={"Reference for " + p.name}
                />
              )}
              <div className="person-heading">
                <h3>{p.name}</h3>
                {p.memorial && <span className="badge">Always with us</span>}
                {emails?.[p.id] && <span className="badge">{emails[p.id].status === "joined" ? "Reads this family" : "Invited to read"}</span>}
              </div>
              <p>{p.relationship || p.kind}</p>
              <p className="muted">
                {p.appearance || "Their photo will help establish their look."}
              </p>
              {stage!=='photos'&&<button className="quiet" onClick={() => setEditing(p)}>
                Edit details →
              </button>}
              {stage!=='members'&&<>
              <GooglePhotos familyId={id} personId={p.id} remaining={6-refs.length} onSaved={saved}/>
              <label className={"upload"+(busy || refs.length >= 6?" is-disabled":"")}>
                <span className="upload-label">Reference photos · {refs.length}/6</span>
                <span className="upload-button">{refs.length >= 6 ? "Six photos saved" : "＋ Upload photos"}</span>
                <input
                  type="file"
                  accept="image/jpeg,image/png,image/webp"
                  multiple
                  disabled={busy || refs.length >= 6}
                  onChange={(e) => {
                    const files = Array.from(e.target.files ?? []);
                    e.target.value = "";
                    void run(async () => {
                      if (files.length + refs.length > 6)
                        throw new Error(
                          "Choose up to six photos in total for this cast member.",
                        );
                      const occupied = new Set(refs.map((r) => r.position));
                      for (const file of files) {
                        if (file.size > 5 * 1024 * 1024)
                          throw new Error("Each photo must be under 5 MB.");
                        if (
                          !["image/jpeg", "image/png", "image/webp"].includes(
                            file.type,
                          )
                        )
                          throw new Error("Choose a JPEG, PNG or WebP photo.");
                        let position = 0;
                        while (occupied.has(position)) position++;
                        occupied.add(position);
                        const path = `${id}/${p.id}/${crypto.randomUUID()}`;
                        const uploaded = await db!.storage
                          .from("family-references")
                          .upload(path, file, {
                            contentType: file.type,
                            upsert: false,
                          });
                        if (uploaded.error) {
                          // Contributors can always upload, so a policy refusal
                          // here means the family's stored-photo ceiling.
                          if (/row-level security|policy/i.test(uploaded.error.message))
                            throw new Error("This photo could not be saved. This family may have reached its limit of 200 stored photos; remove ones you no longer need and try again.");
                          throw uploaded.error;
                        }
                        const result = await db!
                          .from("reference_photos")
                          .insert({
                            family_id: id,
                            person_id: p.id,
                            object_path: path,
                            position,
                          });
                        if (result.error) {
                          await db!.storage
                            .from("family-references")
                            .remove([path]);
                          throw result.error;
                        }
                      }
                      await saved();
                    });
                  }}
                />
              </label>
              <div className="reference-list">
                {refs.map((r, i) => (
                  <span key={r.id}>
                    <PrivateImage compact bucket="family-references" path={r.object_path} alt={`Photo ${i + 1} of ${p.name}`} />
                    <button
                      className="quiet"
                      disabled={busy}
                      aria-label={`Remove photo ${i + 1} for ${p.name}`}
                      onClick={() =>
                        void run(async () => {
                          const deleted = await db!
                            .from("reference_photos")
                            .delete()
                            .eq("id", r.id);
                          if (deleted.error) throw deleted.error;
                          const removed = await db!.storage
                            .from("family-references")
                            .remove([r.object_path]);
                          await saved();
                          if (removed.error)
                            throw new Error(
                              "Reference removed from the profile; stored file cleanup needs a retry.",
                            );
                        })
                      }
                    >
                      ×
                    </button>
                  </span>
                ))}
              </div>
              <p className="muted small">
                For pets, include a clear photo of the named pet. Other subjects
                in the photo won’t become cast members.
              </p>
              </>}
              {owner&&stage!=='photos'&&<button className="quiet" disabled={busy} onClick={()=>{setRemoving(p.id);setConfirmation('')}}>Remove from this cast</button>}
              {removing===p.id&&<form className="confirm-remove" onSubmit={e=>{e.preventDefault();void run(async()=>{await rpc('remove_cast_member',{person_id:p.id,confirmation});setRemoving(null);await saved();const paths=refs.map(r=>r.object_path);if(paths.length){const cleaned=await db!.storage.from('family-references').remove(paths);if(cleaned.error)throw Error('The member was removed. Some stored photo files could not be cleaned up.');}})}}><p>Remove <strong>{p.name}</strong> from this family’s future cast? Past comics stay in the archive. This profile removal cannot be undone.</p><label>Type {p.name} to confirm<input value={confirmation} onChange={e=>setConfirmation(e.target.value)}/></label><button className="danger" disabled={busy||confirmation!==p.name}>Remove cast member</button><button type="button" className="quiet" disabled={busy} onClick={()=>setRemoving(null)}>Cancel</button></form>}
            </article>
          );
        })}
      </div>
      {!data.length && !editing && (
        <section className="empty paper">
          <h2>Who’s in this edition?</h2>
          <p>Add the people and pets who make this family yours.</p>
        </section>
      )}
    </>
  );
}
function StoryJar({ id, run, busy }: { id: string } & Runner) {
  const { data, error, refresh } = useRows("story_moments", id);
  return (
    <>
      <section className="section-heading">
        <div>
          <h2>Little things worth saving</h2>
          <p>
            A phrase, a habit, a tiny everyday moment. No punchline required.
          </p>
        </div>
      </section>
      <form
        className="paper"
        onSubmit={(e) => {
          e.preventDefault();
          const form = e.currentTarget,
            text = String(new FormData(form).get("text"));
          void run(async () => {
            const result = await db!
              .from("story_moments")
              .insert({ family_id: id, text });
            if (result.error) throw result.error;
            form.reset();
            await refresh();
          });
        }}
      >
        <label>
          What made you smile?
          <AutoTextarea
            required
            maxLength={4000}
            name="text"
            placeholder="Who always says they’re ready, then can’t find their shoes?"
          />
        </label>
        <button disabled={busy}>Add to the story jar</button>
      </form>
      {error && <p role="alert">{error}</p>}
      <div className="moments">
        {data.map((m) => (
          <article className="paper" key={m.id}>
            <p>{m.text}</p>
            <button
              className="quiet"
              disabled={busy}
              onClick={() =>
                void run(async () => {
                  const r = await db!
                    .from("story_moments")
                    .delete()
                    .eq("id", m.id);
                  if (r.error) throw r.error;
                  await refresh();
                })
              }
            >
              Remove
            </button>
          </article>
        ))}
      </div>
    </>
  );
}
function Cast({
  family,
  owner,
  run,
  busy,
  onChange,
}: { family: Row; owner: boolean;onChange:()=>Promise<void> } & Runner) {
  const casts = useRows("cast_versions", family.id),
    jobs = useRows("cast_jobs", family.id);
  const cast = [...casts.data].sort((a, b) =>
    b.created_at.localeCompare(a.created_at),
  )[0];
  const current = cast?.visual_revision === family.visual_revision;
  const people=useRows('people',family.id),refs=useRows('reference_photos',family.id);
  const withoutPhotos=people.data.filter(p=>!refs.data.some(r=>r.person_id===p.id));
  const ready=current&&cast?.approved_at&&!cast?.missing?.length;
  useEffect(()=>{const timer=setInterval(()=>{if(document.visibilityState==='visible'){void casts.refresh();void jobs.refresh();void onChange()}},15000);return()=>clearInterval(timer)},[family.id]);
  return (
    <>
      <div className="section-heading">
        <div>
          <h2>A familiar face, before the first funny page.</h2>
          <p>Review everyone’s look before they star in a comic.</p>
        </div>
      </div>
      {(casts.error || jobs.error) && (
        <p role="alert">{casts.error || jobs.error}</p>
      )}
      {cast ? (
        <section className="paper">
          <span className="badge">
            {!current
              ? "Needs a refresh"
              : cast.approved_at
                ? "Approved"
                : "Ready for your review"}
          </span>
          <PrivateImage
            bucket="family-comics"
            path={cast.object_path}
            alt="Family cast preview"
          />
          {cast.missing?.length > 0 && (
            <p>Missing: {cast.missing.join(", ")}</p>
          )}
          {owner && current && !cast.approved_at && !cast.missing?.length && (
            <button
              disabled={busy}
              onClick={() =>
                void run(async () => {
                  await rpc("approve_cast", { cast_id: cast.id });
                  await casts.refresh();
                  await onChange();
                })
              }
            >
              Approve this cast
            </button>
          )}
          {owner&&ready&&!mirroredFamilies.has(family.id)&&!family.production_enabled&&<button disabled={busy} onClick={()=>void run(async()=>{await rpc('enable_production',{fid:family.id});await onChange()})}>Start daily comics</button>}
        </section>
      ) : (
        <section className="paper empty">
          <h2>Your cast preview belongs here.</h2>
          <p>
            Saving people and reference photos queues the latest look for a cast
            preview.
          </p>
          <p className="badge">{!people.data.length?'Add your first cast member':withoutPhotos.length?'Add a photo for each cast member':'Queued for the next cast check'}</p>
          {!!withoutPhotos.length&&<p>Still need photos: {withoutPhotos.map(p=>p.name).join(', ')}</p>}
        </section>
      )}
      <p className="muted">
        {ready
          ? "This look is approved. If you change people or photos, a new preview is prepared around 7 a.m. Pacific for you to review."
          : "Cast previews are prepared each morning around 7 a.m. Pacific. Come back to review yours before starting daily comics."}
      </p>
      {jobs.data
        .filter((j) => j.visual_revision === family.visual_revision)
        .map((j) => (
          <p key={j.id}>
            {j.state==='processing'?'Your cast preview is being drawn.':j.state==='ready'?ready?'Your cast is approved.':current?'Your cast preview is ready to review.':'Your latest cast work is saved.':j.state==='failed'?'We couldn’t finish your cast preview. Check your reference photos; the next morning check can retry while attempts remain.':'Your latest photos and details are saved for the next morning cast check.'}
          </p>
        ))}
    </>
  );
}
function Settings({
  family,
  run,
  busy,
  onChange,
}: { family: Row; onChange: () => Promise<void> } & Runner) {
  const [link, setLink] = useState(""),
    [invites, setInvites] = useState<Row[]>([]),
    [error, setError] = useState("");
  const [deleting,setDeleting]=useState(false),[confirmation,setConfirmation]=useState('');
  async function load() {
    try {
      setInvites(await rpc("list_invitations", { fid: family.id }));
    } catch (e) {
      setError(errorText(e));
    }
  }
  useEffect(() => {
    void load();
  }, [family.id]);
  return (
    <div className="settings-grid">
      <form
        className="paper"
        onSubmit={(e) => {
          e.preventDefault();
          const d = new FormData(e.currentTarget);
          void run(async () => {
            const r = await db!
              .from("families")
              .update(Object.fromEntries(d.entries()))
              .eq("id", family.id)
              .select("id")
              .single();
            if (r.error) throw r.error;
            await onChange();
          });
        }}
      >
        <h2>This family edition</h2>
        <label>
          Name
          <input
            required
            maxLength={100}
            name="name"
            defaultValue={family.name}
          />
        </label>
        <label>
          How everyone fits together
          <AutoTextarea name="relationships" defaultValue={family.relationships} />
        </label>
        <label>
          Humor boundaries
          <AutoTextarea name="boundaries" defaultValue={family.boundaries} />
        </label>
        <label>
          Comic tone
          <input name="tone" defaultValue={family.tone} />
        </label>
        <label>
          Anything to adjust in the cast?
          <AutoTextarea name="cast_notes" defaultValue={family.cast_notes} />
        </label>
        <p className="muted">
          Visual changes queue a new preview for your approval.
        </p>
        <button disabled={busy}>Save family details</button>
      </form>
      <section className="paper">
        <h2>Invite your people</h2>
        <p>
          Contributors help with people and story ideas. Readers only see
          comics. Each invitation works once and expires in seven days.
        </p>
        <form
          onSubmit={(e) => {
            e.preventDefault();
            const role = new FormData(e.currentTarget).get("role");
            void run(async () => {
              const bytes = crypto.getRandomValues(new Uint8Array(32));
              const token = Array.from(bytes, (b) =>
                b.toString(16).padStart(2, "0"),
              ).join("");
              await rpc("create_invitation", {
                fid: family.id,
                member_role: role,
                token,
              });
              setLink(location.origin + "/#invite=" + token);
              await load();
            });
          }}
        >
          <label>
            Invite as
            <select name="role">
              <option value="reader">Reader</option>
              <option value="contributor">Contributor</option>
            </select>
          </label>
          <button disabled={busy}>Create invitation link</button>
        </form>
        {link && (
          <div className="notice">
            <label>
              Copy this link now
              <input
                value={link}
                readOnly
                onFocus={(e) => e.currentTarget.select()}
              />
            </label>
            <button
              onClick={() =>
                void run(async () => {
                  await navigator.clipboard.writeText(link);
                })
              }
            >
              Copy invitation
            </button>
            <p className="small">
              Only share with the person you’re inviting. This link grants
              access to this family.
            </p>
          </div>
        )}
        {error && <p role="alert">{error}</p>}
        {invites.map((i) => (
          <div className="invitation-row" key={i.id}>
            <span>
              {i.role} ·{" "}
              {i.used_at
                ? "Accepted"
                : i.revoked_at
                  ? "Revoked"
                  : new Date(i.expires_at) < new Date()
                    ? "Expired"
                    : "Pending"}
            </span>
            {!i.used_at && !i.revoked_at && (
              <button
                className="quiet"
                disabled={busy}
                onClick={() =>
                  void run(async () => {
                    await rpc("revoke_invitation", { invitation_id: i.id });
                    setLink("");
                    await load();
                  })
                }
              >
                Revoke
              </button>
            )}
          </div>
        ))}
        <hr />
        <h3>Comics without an account</h3>
        <p>
          Reading without an account isn’t available yet. For now, invite
          someone as a Reader above, or use Share on any comic to send them the
          picture.
        </p>
        <hr />
        <h3>Daily comics</h3>
        <p>
          {mirroredFamilies.has(family.id)?'Arriving every morning':family.production_enabled ? "On" : "Paused"} · Pacific time
        </p>
        {family.production_enabled && (
          <button
            disabled={busy}
            onClick={() =>
              void run(async () => {
                await rpc("pause_production", { fid: family.id });
                await onChange();
              })
            }
          >
            Pause daily comics
          </button>
        )}
        <p className="muted">
          {mirroredFamilies.has(family.id)?'This family’s comics arrive each morning from your original Family Funnies collection.':'After approving your cast, choose Start daily comics on the Cast tab. Comics are generated each morning around 8 a.m. Pacific and appear after generation finishes.'}
        </p>
        <div className="danger-zone"><h3>Remove this family</h3><p>Move this family to your Trash. It disappears from everyone’s bookshelf and new production stops. A family manager can restore it from My families.</p>{!deleting?<button className="quiet" onClick={()=>setDeleting(true)}>Move family to Trash</button>:<form onSubmit={e=>{e.preventDefault();void run(async()=>{await rpc('trash_family',{fid:family.id,confirmation});await onChange()})}}><label>Type {family.name} to confirm<input value={confirmation} onChange={e=>setConfirmation(e.target.value)}/></label><button className="danger" disabled={busy||confirmation!==family.name}>Move to Trash</button><button type="button" className="quiet" disabled={busy} onClick={()=>setDeleting(false)}>Cancel</button></form>}</div>
      </section>
    </div>
  );
}
function FamilyTrash({run,busy,onChange}:Runner&{onChange:()=>Promise<void>}){
 const [trash,setTrash]=useState<Row[]>([]),[error,setError]=useState('');
 const [purging,setPurging]=useState<string|null>(null),[confirmation,setConfirmation]=useState('');
 async function load(){try{setTrash(await rpc('list_family_trash',{}));setError('')}catch(e){setError(errorText(e))}}
 useEffect(()=>{void load()},[]);
 // Stored files go first; the database refuses to drop a family that still has any.
 async function purge(f:Row){
  try{
   for(let pass=0;;pass++){
    const files:Row[]=await rpc('list_trash_files',{fid:f.id});
    if(!files.length)break;
    if(pass>=40)throw Error('This family has more stored files than one pass can clear. Choose Delete forever again to continue.');
    for(const bucket of new Set(files.map(x=>x.bucket))){
     const paths=files.filter(x=>x.bucket===bucket).map(x=>x.path);
     for(let i=0;i<paths.length;i+=100){const removed=await db!.storage.from(bucket).remove(paths.slice(i,i+100));if(removed.error)throw Error('Some stored photos or comics could not be deleted. Nothing else was removed; try again.');}
    }
   }
   await rpc('purge_family',{fid:f.id,confirmation});
  }catch(e){
   if((e as {code?:string})?.code==='PGRST202')throw Error('Permanent delete is not switched on for this app yet. The family is still safely in your Trash.');
   throw e;
  }
  setPurging(null);setConfirmation('');await load();await onChange();
 }
 return <details className="trash-list"><summary>Family Trash{trash.length?` (${trash.length})`:''}</summary><p className="muted small">Only managers can see and restore their trashed families. Restoring leaves daily production paused until you choose to resume. Deleting forever erases the family, its people, photos and comics for everyone.</p>{error&&<p role="alert">{error}</p>}{!trash.length&&<p>Your Trash is empty.</p>}{trash.map(f=><div className="trash-row" key={f.id}><strong>{f.name}</strong><span className="trash-actions"><button className="quiet" disabled={busy} onClick={()=>void run(async()=>{await rpc('restore_family',{fid:f.id});await onChange();await load()})}>Restore family</button>{purging!==f.id&&<button className="quiet" disabled={busy} onClick={()=>{setPurging(f.id);setConfirmation('')}}>Delete forever</button>}</span>{purging===f.id&&<form className="confirm-remove" onSubmit={e=>{e.preventDefault();void run(()=>purge(f))}}><p>Permanently delete <strong>{f.name}</strong>? Its people, reference photos, story jar and every comic are erased for all members. This cannot be undone.</p><label>Type {f.name} to confirm<input value={confirmation} autoComplete="off" onChange={e=>setConfirmation(e.target.value)}/></label><button className="danger" disabled={busy||confirmation!==f.name}>{busy?'Deleting…':'Delete forever'}</button><button type="button" className="quiet" disabled={busy} onClick={()=>setPurging(null)}>Cancel</button></form>}</div>)}</details>
}
createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
