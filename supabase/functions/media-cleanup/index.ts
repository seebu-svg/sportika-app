// Schedule daily using Supabase Cron. Invoke using the service-role Bearer token.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
Deno.serve(async (request: Request) => {
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  if (request.method !== 'POST' || request.headers.get('authorization') !== `Bearer ${key}`) {
    return new Response('Forbidden', { status: 403 });
  }
  const client = createClient(Deno.env.get('SUPABASE_URL')!, key);
  const { data, error } = await client.rpc('module_media_orphans');
  if (error) return new Response('Candidate lookup failed', { status: 500 });
  let deleted = 0;
  for (const bucket of ['team-media', 'tournament-media', 'match-media']) {
    const paths = data.filter((row: {bucket_id: string}) => row.bucket_id === bucket)
      .map((row: {name: string}) => row.name);
    if (paths.length) {
      const result = await client.storage.from(bucket).remove(paths);
      if (result.error) return new Response('Cleanup failed; retry next run', { status: 500 });
      deleted += paths.length;
    }
  }
  return Response.json({ deleted });
});
