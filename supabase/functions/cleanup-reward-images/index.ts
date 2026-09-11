import { createClient } from 'npm:@supabase/supabase-js@2'

const bucketName = 'reward-images'
const pageSize = 1000
const deleteBatchSize = 100
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
const objectPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(jpg|webp)$/i

const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  })

Deno.serve(async (request) => {
  if (request.method !== 'POST') {
    return json(405, { error: 'method_not_allowed' })
  }

  const authorization = request.headers.get('authorization')
  const token = authorization?.match(/^Bearer\s+(.+)$/i)?.[1]
  if (!authorization || !token) {
    return json(401, { error: 'authentication_required' })
  }

  const url = Deno.env.get('SUPABASE_URL')
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
  if (!url || !anonKey) {
    return json(500, { error: 'server_configuration_error' })
  }

  const supabase = createClient(url, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: authorization } },
  })
  const { data: userData, error: userError } = await supabase.auth.getUser(token)
  if (userError || !userData.user) {
    return json(401, { error: 'authentication_required' })
  }

  const ownerId = userData.user.id
  const bucket = supabase.storage.from(bucketName)
  const objectPaths: string[] = []

  try {
    for (let offset = 0; ; offset += pageSize) {
      const { data: ownerEntries, error } = await bucket.list(ownerId, {
        limit: pageSize,
        offset,
        sortBy: { column: 'name', order: 'asc' },
      })
      if (error) throw error

      for (const entry of ownerEntries ?? []) {
        if (entry.id && objectPattern.test(entry.name)) {
          objectPaths.push(`${ownerId}/${entry.name}`)
          continue
        }
        if (!uuidPattern.test(entry.name)) continue
        const rewardPrefix = `${ownerId}/${entry.name}`
        for (let objectOffset = 0; ; objectOffset += pageSize) {
          const { data: objects, error: objectError } = await bucket.list(
            rewardPrefix,
            {
              limit: pageSize,
              offset: objectOffset,
              sortBy: { column: 'name', order: 'asc' },
            },
          )
          if (objectError) throw objectError
          for (const object of objects ?? []) {
            if (object.id && objectPattern.test(object.name)) {
              objectPaths.push(`${rewardPrefix}/${object.name}`)
            }
          }
          if ((objects?.length ?? 0) < pageSize) break
        }
      }
      if ((ownerEntries?.length ?? 0) < pageSize) break
    }

    for (let index = 0; index < objectPaths.length; index += deleteBatchSize) {
      const { error } = await bucket.remove(
        objectPaths.slice(index, index + deleteBatchSize),
      )
      if (error) throw error
    }
    return json(200, { deleted: objectPaths.length })
  } catch (_error) {
    return json(500, { error: 'storage_cleanup_failed' })
  }
})
