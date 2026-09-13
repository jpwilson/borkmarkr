(function (root) {
  class OpenSignalStore {
    constructor({ session, request, read, write, device, changed = () => {} }) {
      Object.assign(this, { session, request, read, write, device, changed });
      this.rows = new Map(); this.owner = null; this.running = false;
      this.restore();
    }
    restore() {
      this.rows.clear(); this.owner = this.session()?.user_id || null;
      if (!this.owner) return;
      try {
        const data = JSON.parse(this.read("bm.open-signals") || "null");
        if (data?.owner === this.owner) for (const r of data.rows || []) this.rows.set(r.id, r);
      } catch { /* no cached signals */ }
    }
    persist() { this.write("bm.open-signals", JSON.stringify({ owner:this.owner, rows:[...this.rows.values()] })); }
    adopt(rows) {
      for (const row of rows) {
        const old = this.rows.get(row.id);
        this.rows.set(row.id, { ...row,
          open_count: Math.max(old?.open_count || 0, row.open_count || 0),
          last_opened_at: [old?.last_opened_at, row.last_opened_at].filter(Boolean).sort((a,b) => Date.parse(a)-Date.parse(b)).at(-1) || null,
        });
      }
    }
    seed(id, count, at) {
      if (!this.session() || !count) return;
      if (this.owner !== this.session().user_id) this.restore();
      const key = this.device + ":" + id;
      if (this.rows.has(key)) return;
      const now = new Date().toISOString();
      this.rows.set(key, {id:key, owner_id:this.owner, bookmark_id:id, device_id:this.device,
        open_count:count, last_opened_at:at || null, created_at:now, updated_at:now});
      this.persist();
    }
    bump(id) {
      if (!this.session()) return;
      if (this.owner !== this.session().user_id) this.restore();
      const key = this.device + ":" + id;
      const now = new Date().toISOString(), old = this.rows.get(key);
      this.rows.set(key, {id:key, owner_id:this.owner, bookmark_id:id, device_id:this.device,
        open_count:(old?.open_count || 0) + 1, last_opened_at:now, created_at:old?.created_at || now, updated_at:now});
      this.persist(); this.changed();
    }
    aggregate(id) {
      const rows = [...this.rows.values()].filter(r => r.bookmark_id === id);
      return { n:rows.reduce((n,r) => n + r.open_count, 0),
        at:rows.map(r => r.last_opened_at).filter(Boolean).sort((a,b) => Date.parse(a)-Date.parse(b)).at(-1) || null };
    }
    async sync() {
      if (!this.session() || this.running) return;
      if (this.owner !== this.session().user_id) this.restore();
      const owner = this.owner;
      this.running = true;
      try {
        const server = new Map();
        let complete = false;
        for (let page = 0; page < 30; page++) {
          const rows = await this.request(`/rest/v1/bookmark_opens?select=*&owner_id=eq.${owner}&order=updated_at.asc,id.asc&limit=1000&offset=${page * 1000}`);
          if (this.session()?.user_id !== owner) return;
          for (const row of rows) server.set(row.id, row);
          this.adopt(rows);
          if (rows.length < 1000) { complete = true; break; }
        }
        if (!complete) throw new Error("Revisit backup is incomplete. Please retry.");
        const pending = [...this.rows.values()].filter(r => r.open_count > (server.get(r.id)?.open_count ?? -1));
        for (let i = 0; i < pending.length; i += 200) {
          const back = await this.request("/rest/v1/bookmark_opens?on_conflict=owner_id,id", {
            method:"POST", body:pending.slice(i,i+200), headers:{Prefer:"resolution=merge-duplicates,return=representation"},
          });
          if (this.session()?.user_id !== owner) return;
          this.adopt(back || []);
        }
        this.persist(); this.changed();
      } finally { this.running = false; }
    }
  }
  root.OpenSignalStore = OpenSignalStore;
})(globalThis);
