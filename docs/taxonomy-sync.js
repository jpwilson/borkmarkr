/* Durable, owner-scoped custom taxonomy. Pure transport/store for testability. */
(function (root) {
  class TaxonomyStore {
    constructor({ session, request, read, write, changed = () => {}, error = () => {} }) {
      Object.assign(this, { session, request, read, write, changed, error });
      this.topics = new Map(); this.subtopics = new Map(); this.pending = new Map();
      this.owner = null; this.running = false;
      this.restore();
    }
    reset() {
      this.topics.clear(); this.subtopics.clear(); this.pending.clear(); this.owner = null;
    }
    restore() {
      this.reset();
      this.owner = this.session()?.user_id || null;
      try {
        const data = JSON.parse(this.read("bm.taxonomy") || "null");
        if (!this.owner || data?.owner !== this.owner) return;
        for (const kind of ["topics", "subtopics"])
          for (const row of data[kind] || []) this[kind].set(row.id, row);
        for (const [key, row] of data.pending || []) this.pending.set(key, row);
      } catch { /* fresh cache */ }
    }
    persist() {
      this.write("bm.taxonomy", JSON.stringify({ owner: this.owner,
        topics: [...this.topics.values()], subtopics: [...this.subtopics.values()],
        pending: [...this.pending] }));
    }
    adopt(kind, rows) {
      for (const row of rows) {
        if (!row.id || !Number.isFinite(Date.parse(row.updated_at))) throw new Error("Invalid topic backup.");
        const old = this[kind].get(row.id);
        if (!old || Date.parse(old.updated_at) < Date.parse(row.updated_at)) this[kind].set(row.id, row);
      }
    }
    put(kind, fields) {
      if (!["topics", "subtopics"].includes(kind) || !this.session()) throw new Error("Sign in to save a topic.");
      if (this.owner !== this.session().user_id) this.restore();
      const now = new Date().toISOString();
      const row = { ...this[kind].get(fields.id), ...fields, owner_id: this.owner,
        created_at: this[kind].get(fields.id)?.created_at || now, updated_at: now, deleted_at: fields.deleted_at || null };
      this[kind].set(row.id, row); this.pending.set(kind + ":" + row.id, row);
      this.persist(); this.changed();
      this.sync().catch(this.error);
      return row;
    }
    async sync() {
      const session = this.session();
      if (!session || this.running) return;
      if (this.owner !== session.user_id) this.restore();
      const owner = this.owner;
      this.running = true;
      try {
        for (const [key, row] of [...this.pending]) {
          const kind = key.slice(0, key.indexOf(":"));
          const back = await this.request("/rest/v1/custom_" + kind + "?on_conflict=owner_id,id", {
            method: "POST", body: [row], headers: { Prefer: "resolution=merge-duplicates,return=representation" },
          });
          if (this.session()?.user_id !== owner) return;
          this.adopt(kind, back || []);
          if (this.pending.get(key)?.updated_at === row.updated_at) this.pending.delete(key);
          this.persist();
        }
        for (const kind of ["topics", "subtopics"]) {
          let complete = false;
          for (let page = 0; page < 30; page++) {
            const rows = await this.request(`/rest/v1/custom_${kind}?select=*&owner_id=eq.${owner}&order=updated_at.asc,id.asc&limit=1000&offset=${page * 1000}`);
            if (this.session()?.user_id !== owner) return;
            this.adopt(kind, rows); this.persist();
            if (rows.length < 1000) { complete = true; break; }
          }
          if (!complete) throw new Error("Your topic backup is incomplete. Please retry.");
        }
        this.changed();
      } finally { this.running = false; }
    }
  }
  root.TaxonomyStore = TaxonomyStore;
})(globalThis);
