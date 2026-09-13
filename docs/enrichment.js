const Enrichment = {
  due(row, now = Date.now()) {
    return !row.deleted_at && (row.enrichment_version || 0) < 2 && (row.enrichment_attempts || 0) < 3
      && (!row.enrichment_attempted_at || now - Date.parse(row.enrichment_attempted_at) >= 3600000);
  },
  preview(row, preview, fallbackTitle) {
    const body = SavedContent.excerpt(preview.description);
    const usefulTitle = preview.title && preview.title !== fallbackTitle && !/ on (X|Instagram|Threads)$/i.test(preview.title);
    return {
      title: row.title_edited !== true && (!row.title || row.title === fallbackTitle) ? preview.title || row.title : row.title,
      body_text: body,
      image_url: preview.image_url || row.image_url || null,
      author: preview.author || null,
      enrichment_version: body || usefulTitle ? 2 : row.enrichment_version || 0
    };
  }
};

class EnrichmentQueue {
  constructor({session,rows,preview,save,changed,clock=Date.now}) {
    Object.assign(this,{session,rows,preview,save,changed,clock});
    this.busy=false; this.attempted=new Map();
  }
  async run({id, force=false} = {}) {
    const owner=this.session()?.user_id;
    if (!owner || this.busy) return {busy:this.busy,updated:0,failed:0};
    this.busy=true;
    const status={updated:0,failed:0,busy:false};
    try {
      const rows=this.rows().filter(r=>(!id || r.id===id) && !r.deleted_at && (force || (Enrichment.due(r,this.clock()) && this.clock()-(this.attempted.get(owner+":"+r.id)||0)>=3600000))).slice(0,4);
      await Promise.all(rows.map(async row=>{
        const stamp=row.updated_at;
        this.attempted.set(owner+":"+row.id,this.clock());
        try {
          const result=await this.preview(row);
          if (this.session()?.user_id!==owner) return;
          const current=this.rows().find(r=>r.id===row.id);
          if (!current || current.deleted_at || current.updated_at!==stamp) return;
          const saved=await this.save(current,result,stamp);
          if (this.session()?.user_id===owner && saved?.length) { this.changed(saved); status.updated++; }
        } catch { status.failed++; /* local cooldown; server retains prior data */ }
      }));
    } finally { this.busy=false; }
    return status;
  }
}
