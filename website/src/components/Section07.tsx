import React, { useEffect, useRef } from 'react';
import gsap from 'gsap';

export const Section07: React.FC = () => {
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const ctx = gsap.context(() => {
      gsap.from('.board-row', {
        opacity: 0,
        x: -30,
        duration: 0.5,
        stagger: 0.1,
        scrollTrigger: {
          trigger: containerRef.current,
          start: 'top 70%',
        }
      });
    }, containerRef);
    return () => ctx.revert();
  }, []);

  const entries = [
    { rank: '01', name: 'J.DOE', score: '98.41' },
    { rank: '02', name: 'SPIT_KING', score: '96.22' },
    { rank: '03', name: 'UNKNOWN_99', score: '94.70' },
    { rank: '04', name: 'USER_882', score: '92.15' },
    { rank: '05', name: 'YOU', score: '91.20', isYou: true },
    { rank: '06', name: 'A.SMITH', score: '88.04' },
  ];

  return (
    <section ref={containerRef} className="responsive-section" style={{ minHeight: '100vh', padding: '10vw', backgroundColor: 'var(--color-black)', color: 'var(--color-bg)' }}>
      <h2 className="responsive-h2" style={{ fontSize: '6vw', textTransform: 'uppercase', marginBottom: '2vh', letterSpacing: '-0.02em', color: 'var(--color-bg)', lineHeight: 1 }}>
        SPIT OLYMPICS
      </h2>
      <p className="responsive-mono" style={{ fontFamily: 'var(--font-technical)', opacity: 0.5, marginBottom: '8vh', fontSize: '1.2vw' }}>
        GLOBAL_LEADERBOARD // LIVE_DATA
      </p>

      <div style={{ display: 'flex', flexDirection: 'column', gap: '3vh' }}>
        {entries.map((entry, idx) => (
          <div key={idx} className="board-row responsive-list-item" style={{
            display: 'flex',
            justifyContent: 'space-between',
            borderBottom: entry.isYou ? '2px solid var(--color-acid-green)' : '1px solid rgba(243, 241, 234, 0.2)',
            paddingBottom: '2vh',
            color: entry.isYou ? 'var(--color-acid-green)' : 'var(--color-bg)',
            fontFamily: 'var(--font-technical)',
            fontSize: '2vw'
          }}>
            <div style={{ display: 'flex', gap: '4vw' }}>
              <span style={{ opacity: 0.5 }}>{entry.rank}</span>
              <span>{entry.name}</span>
            </div>
            <div style={{ fontWeight: 600 }}>
              {entry.score}
            </div>
          </div>
        ))}
      </div>
    </section>
  );
};
