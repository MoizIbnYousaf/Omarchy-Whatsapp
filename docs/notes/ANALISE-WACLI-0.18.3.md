# Análise de impacto: desafixar o wacli (mínimo 0.17.1, testado 0.18.3)

Base: snapshot upstream v0.14.0 (commit `51ce7fc`) contra wacli `v0.17.1` e `v0.18.3` (fontes, binários, release notes 0.17.2..0.18.3 e diff da árvore de `--help`). Caminhos do app são relativos ao snapshot; caminhos `internal/…`/`cmd/…` são do wacli. Os experimentos usaram só stores descartáveis e comandos locais, sem `auth`, `sync` nem rede.

## 1. Resumo executivo

1. **Decisão:** o fork aceita wacli `>= 0.17.1` e usa `0.18.3` como versão testada no CI. O upstream exige exatamente `0.17.1`.
2. **O que quebra:** só o portão de versão exata (RT-01). Hoje `scripts/install:90-93` aborta com 0.18.3, e `scripts/check-wacli-parity` (gate de `scripts/test:35`) falha com a folha nova `groups participants list`.
3. **Store:** `schema.sql` é idêntico entre as tags. A migração 26 só cria dois índices e restringe o trigger `messages_au`. Todas as queries do helper devolveram saída idêntica contra stores reais das duas versões, e o downgrade 0.18.3 → 0.17.1 abre sem erro.
4. **Runtime:** nenhum conflito bloqueante. Os riscos reais são baixos ou médios: daemon 0.17.1 ainda rodando depois de trocar o binário (RT-02), parse frágil do envelope JSON (RT-03) e o marcador `SESSION_REVOKED` ignorado (RT-06).
5. **Antes de instalar:** trocar a igualdade de versão por piso semântico em `scripts/install` e alinhar `WACLI_PARITY_VERSION`, a contagem `operation_count == 103` e `check-wacli-parity` à semântica "mínimo 0.17.1 / testado 0.18.3".
6. **Antes do release do fork:** atualizar os testes que fixam `0.17.1`/`103`, pôr 0.18.3 com sha256 no CI e acrescentar um teste de contrato de schema gerado pelo binário (SQL-1).
7. **Ganhos com 0.18.x:** recibo de leitura delegado ao `sync --follow` (0.18.2), que deixa de derrubar o sync a cada abertura de chat; roster completo de grupos via `--refresh-groups` (0.18.0); stdout limpo de diagnósticos do libsignal (0.18.3); sinal `session_revoked` (0.18.3); edições cifradas, comentários e álbuns indexados (0.17.2/0.18.3).
8. **Ganho que não depende de versão:** `media download --read-only --output` já existe no 0.17.1 e elimina o yield de até 180 s por download.
9. **Superfície nova:** uma folha (`groups participants list`, `local-read`) e uma flag (`send text --allow-self`). As duas exigem 0.18.0+ e precisam de detecção de versão, porque o helper não sonda o wacli em runtime.
10. **Próximos passos:** as funcionalidades de maior valor (filtros/arquivadas, paginação, busca global FTS5, backfill) usam dados que já estão no store e não dependem da versão.

## 2. Conflitos confirmados

| id | severidade | arquivo:linha | impacto | correção |
|---|---|---|---|---|
| RT-01 | **bloqueante** | `scripts/install:90-93` (+ `scripts/install:201-203`, `370-372`; `scripts/check-wacli-parity:84-93`, `99-107`; `bin/omawhatsapp:120`, `225-340`, `3318-3325`, `3750-3751`; `tests/test_backend.py:1216-1226`; `tests/test_backend_hardening.py:793`, `797`; `.github/workflows/validate.yml:34-43`) | Com 0.18.3, `if [[ $wacli_version != 0.17.1 ]]` aborta o instalador ("requires exactly wacli 0.17.1"). `check-wacli-parity` falha com `parity: unclassified wacli leaf: groups participants list`, e `_transport_path` recusa a folha ("not in the wacli 0.17.1 parity registry"). Se a folha só for acrescentada ao registro, o script passa a falhar contra o piso 0.17.1 (`registered leaf missing from wacli`). No 0.17.1, `groups participants list` sem `--jid` devolve o help com rc=0 (verificado). | (1) Portão semver `>= 0.17.1` no install, com aviso acima da versão testada. (2) Pôr `('groups','participants','list')` em `local-read` e em `WACLI_GROUP_JID_OPERATIONS`, o que torna `--jid` obrigatório (`bin/omawhatsapp:3408-3410`); no 0.17.1 a chamada falha limpa com `unknown flag: --jid`, rc=1. (3) `jq -e … operation_count == 103` passa a comparar com a contagem calculada para a versão instalada. (4) Em `check-wacli-parity`, `stale` só é aceito para folhas com versão mínima acima da instalada, e `missing` continua proibido. (5) Atualizar testes, CI (matriz 0.17.1 + 0.18.3 com sha256) e docs: `README.md:43,109,186`, `docs/PARITY.md:11,17-18`, `docs/ARCHITECTURE.md:82`, `docs/TESTING.md:19-20`, `docs/MULTIACCOUNT-SCOPE.md:10,12`, `skills/omawhatsapp/references/wacli-parity.md:17`. |
| SQL-1 | média | `tests/test_backend.py:28-80` (mensagens genéricas em `bin/omawhatsapp:1636,1653,1673,1687,1986,2445,2594,2614`; sem `exc` também em `1702`, `2562`) | O fixture `SCHEMA` é escrito à mão, nenhum teste gera `wacli.db` com o binário e `check-wacli-parity` só compara `--help`. Hoje nada quebra, mas sem teto de versão uma coluna renomeada numa 0.19 viraria "The local WhatsApp index could not be read." sem diagnóstico. | Teste de contrato no CI que cria a store com cada binário (0.17.1 e 0.18.3) e roda os métodos de leitura do helper; teto validado (aviso no install ou `SELECT max(version) FROM schema_migrations` comparado a 26); incluir `str(exc)` nas mensagens. |
| RT-02 | média (na prática, transitória) | `bin/omawhatsapp:1360-1362` (`_locked`), `1459-1464` (`_mutate`) | Se `~/.local/bin/wacli` for trocado por fora sem reiniciar `wacli-sync(@).service`, o CLI 0.18.2+ delega `chats mark-read`/`mark-unread` ao daemon 0.17.1 (`cmd/wacli/chats_state.go:127-151`). O daemon aceita (`sendDelegateVersion = 1` nas duas versões) e responde `unsupported send kind "mark_read"` (0.17.1 `cmd/wacli/send_ipc.go:296`). `_locked` não reconhece esse texto, então não há yield e o erro técnico aparece a cada recibo automático (`plugins/omawhatsapp/Service.qml:285`). Some na primeira escrita não delegada que faça yield (pin/archive/mute; `systemctl stop/start` em `bin/omawhatsapp:1404/1417`). Quem atualiza pelo instalador não é afetado, porque `scripts/install:353-366` reinicia as units. Não reproduzido ao vivo (limite de caminho AF_UNIX no scratchpad). | Em `_mutate`, tratar `unsupported send kind` e `unsupported send delegate version` como delegação indisponível e seguir o caminho de yield. Teste unitário com stderr JSON contendo esse erro. Documentar que o wacli deve ser atualizado pelo instalador. |
| RT-03 | baixa | `bin/omawhatsapp:2630-2643` (`_envelope`); `74` (`MAX_PROCESS_ERROR`); `447-516` (`run_bounded`); `3697-3718` (`_transport_result`) | `_envelope` faz `json.loads(result.stdout.strip() or result.stderr.strip())` no texto inteiro. No piso 0.17.1 (estado atual do upstream), um aviso do libsignal em stdout transforma sucesso em "WhatsApp rejected the request.". No 0.18.3 (`internal/wa/logger.go:17-22`, `53`) os avisos vão para stderr, e só estragam a mensagem de caminhos que já falharam. O kill por stderr > 64 KiB exigiria mais de 300 avisos num processo; frequência não medida. | Parsear a última linha JSON válida de stdout e depois de stderr, tanto em `_envelope` quanto em `_transport_result`. Não afrouxar o teto sem medir. |
| RT-04 / SQL-2 | baixa (defeito anterior) | `bin/omawhatsapp:2546-2549` (`members()`) | 0.18.x `refreshGroups` chama `storeGroupInfo` → `ReplaceGroupParticipants` (`internal/app/bootstrap.go:48,54-81`), e as units usam `--refresh-groups` (`systemd/user/wacli-sync.service:11`, `wacli-sync@.service:13`). Todo grupo, inclusive os silenciosos, passa a ter roster a cada start. `members()` deriva `phone` com `SUBSTR(jid, …)` também para `@lid`, e o mesmo SUBSTR serve de fallback de nome, então os dígitos do LID aparecem como telefone ou nome. No 0.17.1 isso já acontecia em todo grupo com mensagem (`wacli-src-0.17.1/internal/app/sync.go:451-471`); a 0.18.x só amplia o alcance. Efeito cosmético: `_validated_mentions` (`2663-2679`) compara só o JID. | Em `members()`, `phone = ''` quando `candidates.jid LIKE '%@lid'` (ignorando também `contacts.phone`) e fallback de nome `'WhatsApp member'`. Deduplicar via `whatsmeow_lid_map` fica como melhoria opcional. |
| RT-05 | baixa | `plugins/omawhatsapp/Service.qml:285` (disparado por `selectChat`, `226-249`) | No piso 0.17.1, `mark-read` não é delegado (não há `case "mark_read"` em `wacli-src-0.17.1/cmd/wacli/send_ipc.go:274-296`). Cada seleção de chat com recibos ligados passa por `_yield_active_sync` → `systemctl stop`/`start`, e cada start reexecuta `migrateHistoricalLIDs`, app-state e `--refresh-groups`. Com daemon 0.18.2+ (`send_ipc.go:307`) o caminho atual já aproveita a delegação, sem mudar código. | Nenhuma mudança obrigatória. Opcional: com a sonda de versão, desligar ou limitar recibos automáticos quando a versão for `< 0.18.2`, ou documentar 0.18.2 como piso efetivo para recibos. |
| RT-06 | baixa | `bin/omawhatsapp:3981-3983` (`session_ready`), `655-656` e `679` (`link_account`/`_finalize_link`) | `session_ready` (ExecCondition de `wacli-sync@.service`) e `link_account` só testam se `session.db` existe. Depois de um logout remoto, o 0.18.3 grava `<store>/SESSION_REVOKED` e `doctor` passa a reportar `authenticated:false, session_revoked:true, connection_state:"logged_out"` (testado). Mesmo assim, a unit continua liberada (`Restart=on-failure`, 10 s) e `link_account` recusa revincular uma conta nomeada. O comportamento já existia no 0.17.1. | `session_ready` retorna falso quando há `session_revoked:true` (ou o marcador). Como `ClearSessionRevoked` só roda depois de `Connected` (`internal/app/session_state.go:47-55`, `94-103`), `link_account` precisa aceitar revincular quando existem `session.db` e `SESSION_REVOKED`. |
| RT-08 | baixa | `bin/omawhatsapp:3402-3405` (`_validate_transport_targets`) | Não há allowlist de flags por folha, então `send text --allow-self` (0.18.0, `cmd/wacli/send.go:170`, `119-120`) passa pelo gateway se o self-chat estiver indexado. No 0.17.1 falha limpo com `unknown flag: --allow-self`. Não amplia privilégio: quem tem `whatsapp-write` já envia para qualquer chat indexado. Na UI, `send()` (`2681-2699`) nunca passa a flag, e o self-chat falha nas duas versões. | Decidir a política: bloquear `--allow-self` no gateway ou exigir autorização própria (ex.: `whatsapp-write:allow-self`). Se a UI for suportar self-chat, passar a flag só quando o chat for o JID vinculado e a versão for `>= 0.18.0`. |
| SQL-3 | baixa | `bin/omawhatsapp:2356-2359`, `2452` | Linhas `"(message)"` gravadas pela 0.17.1 (`wacli-src-0.17.1/internal/app/sync.go:707-715`) continuam na store, porque não há migração de dados (`docs/messages.md:30`, "apply on re-ingestion"). O conteúdo novo muda de forma: edições cifradas atualizam a linha-alvo (`sync_events.go:509,643`), comentários trazem `quoted_msg_id` e álbuns recebidos viram a bolha de texto `[Album: N images]` (`internal/wa/messages.go:477-491`), que pode virar `preview`. As edições deixam de somar em `unread_count`. Nenhuma query quebra. | Ocultar os placeholders `(message)` antigos e o cabeçalho de álbum na UI (ver seção 4). Reingestão opcional via `history backfill`. |
| SQL-4 | baixa (defeito anterior) | `bin/omawhatsapp:2229-2257` | Uma edição avança `chats.last_message_ts` (`internal/app/sync.go:392`; `sqlc/queries.sql:1-7`), mas `messages.ts` é preservado (`queries.sql:211`). A heurística do helper trata qualquer avanço como mensagem nova e dispara popup. No 0.18.3, edições cifradas mostram um `preview` que pode não ser a mensagem editada; edições em claro e reações já faziam isso nas duas versões. | Só considerar mensagem nova se `last_message_id` mudar ou `unread` aumentar. |
| SQL-5 | baixa | `internal/store/migrations.go:295-325` (wacli, igual nas duas tags) | `ensureSchema` ignora migrações desconhecidas, então o downgrade 0.18.3 → 0.17.1 funciona (testado com leitura e escrita; `session.db` `whatsmeow_version 15\|8` é idêntico). A contrapartida: a 0.17.1 aceitaria sem aviso uma store de versão futura, e o `SESSION_REVOKED` deixado pela 0.18.x só é apagado por uma 0.18.x conectada. | Documentar que o downgrade é seguro até a migração 26. Se o install permitir voltar de versão, checar `max(version) FROM schema_migrations`. |

**Refutados na verificação**

- RT-07 (download de mídia exige 0.17.2+ para `--read-only --output`): a premissa de versão está errada. A rota já existe no 0.17.1 (`wacli-src-0.17.1/cmd/wacli/media.go:229-287`, `newApp(ctx, flags, !readOnly, false)`). O 0.17.2 só acrescentou a dica na mensagem de lock (`#387`). Não é impacto da migração; virou melhoria sem gate de versão (seção 4).

## 3. Esquema e store

**Achados confirmados:** SQL-1 (sem teste de contrato de schema), SQL-2 (= RT-04, roster `@lid`), SQL-3 (placeholders e forma nova do conteúdo), SQL-4 (heurística de popup) e SQL-5 (downgrade sem proteção). Detalhes na tabela da seção 2.

**Fatos medidos:**
- O `.schema` de stores criadas por `0.17.1` e `0.18.3` difere só em `idx_messages_sender_jid`, `idx_messages_quoted_sender_jid`, no `messages_au` com `WHEN` e na ordem de `app_state_recovery_intents`. `schema_migrations` vai até 25 na 0.17.1 e até 26 na 0.18.3.
- A migração 26 levou 0,86 s numa store de 600k mensagens enquanto o helper lia em loop: 16 leituras, 0 erros, latência máxima 0,061 s. Ela não reconstrói o FTS. `open --read-only` do 0.18.3 numa store v25 não migra e funciona.
- O helper roda (`scratchpad/stores/sqlite-compat/harness.py`) contra stores reais das duas versões produziu `out171.json` == `out183.json`.

**Queries verificadas como compatíveis (áreas seguras):**

| método (bin/omawhatsapp) | colunas lidas |
|---|---|
| `_chat` (1624-1632) + `SUPPORTED_CHAT_WHERE` (114-118) | `chats.jid,kind,name`; `groups.jid,name,is_parent,linked_parent_jid`; `contacts.jid,business_name,full_name,push_name,system_name`; `messages.rowid,chat_jid,ts,chat_name`. Comunidade pai continua oculta. |
| `_chat_any` (1648-1649) | `chats.jid,kind,name` |
| `_message_any` (1668-1669) | `messages.chat_jid,msg_id,deleted_at,reaction_to_id` |
| `_contact_any` (1684) | `contacts.jid` |
| `_group_participant` (1698) | `group_participants.group_jid,user_jid` (PK igual) |
| `_account_chats` (1961-1981) | `chats.jid,kind,last_message_ts,archived,pinned,muted_until,unread_count`; `messages.media_type,text,media_caption,filename,display_text,msg_id,from_me,sender_name,deleted_at,reaction_to_id,ts,rowid`. `applyChatUnread` com `max(unreadCount,0)` é equivalente. |
| `messages()` principal (2369-2386) | `messages.*` usadas (`msg_id … reaction_to_id`), `message_locations.*`, `starred.chat_jid,msg_id` |
| `messages()` citações (2403-2407) | `quoted_msg_id`/`quoted_sender_jid` com a mesma semântica; CommentMessage preenche `quoted_msg_id` de forma compatível |
| `messages()` reações (2414-2433) | `reaction_to_id,reaction_emoji,…` (window function) |
| `members()` (2520-2559) | `group_participants.user_jid,role,group_jid`; `messages.sender_*`; `contacts.*`; `contact_aliases.jid,alias`. O único problema é o SQL-2. |
| `_message` (2586-2590) | `messages.msg_id,sender_jid,sender_name,from_me,text,media_type,deleted_at,chat_jid,reaction_to_id` |
| `download_media` (2607-2610) | `messages.media_type,local_path,media_unavailable_at` (regra de UpsertMessage inalterada) |

Outras áreas verificadas sem impacto:
- `chatKind()` é idêntica nas duas versões: `@lid` continua `unknown` e fora do rail.
- `parseMentionedJIDs` é idêntica.
- A string de lock `store is locked (another wacli is running?)` é idêntica (`internal/lock/lock.go:41-43`), então `_locked` e `_envelope` continuam válidos.
- O formato do envelope JSON não mudou, e os erros saem em stderr nas duas versões.
- As flags do `ExecStart` das units não mudaram (`sync --help` difere só na descrição de `--refresh-groups`).
- O trigger `messages_au` estreito não afeta o helper, que não consulta `messages_fts`.
- O watcher de inotify (`Service.qml:613-637`) filtra `SESSION_REVOKED`, `.send.sock` e os temporários.
- As chaves do `doctor` são um superconjunto.
- O QML nunca invoca o wacli direto.
- Webhooks: o helper só repassa a URL.
- O aviso de truncamento de `groups list` não afeta o helper.
- `chats cleanup` agora falha em exclusão parcial, o que é melhor.
- `[Audio]` continua em `text`.
- A resolução de store (`accounts.go`, `store.go`, `internal/config`, `pathutil`, `fsutil`) não tem diff.
- O reparo de identidade respeita cancelamento, o que reduz o risco de estourar os 20 s de `_systemctl_user`.
- `groups participants list` funciona com `--read-only` (`{"success":true,"data":[]}`).

## 4. Melhorias do wacli a adotar/expor

| mudança | versão | ação | valor | esforço | pontos de contato |
|---|---|---|---|---|---|
| `media download --read-only --output PATH` não pega o lock do store | 0.17.1 (dica em 0.17.2) | adotar: `download_media` via `_run` com `--read-only --output <STATE_DIR/media/<hash-conta>/…>`, sem yield; índice `downloaded-media.json` no molde de `_remember_sent_media`/`_sent_media_hints`, já que `local_path` não é gravado; no transport, `read_only=True` quando há `--output` | alto | 1 dia | `bin/omawhatsapp:2599-2628`, `1221-1275`, `2455-2461`, `3823-3852`; `docs/PARITY.md:167-168`; `skills/omawhatsapp/references/wacli-parity.md:84`; `tests/test_backend.py` |
| `chats mark-read/mark-unread` delegados ao `sync --follow` | 0.18.2 | adotar: o ganho vem sem código. Falta o fallback para daemon antigo (RT-02). O yield não pode ser removido, porque archive/pin/mute/cleanup/groups/profile continuam exigindo lock e o 0.17.1 não delega. | alto | horas | `_locked` 1360-1362, `_mutate`, `chat_action` 2777; `Service.qml:285`; `docs/PARITY.md:67,167`; `docs/ARCHITECTURE.md` |
| folha `groups participants list --jid` (offline, `role`, `updated_at`) | 0.18.0 | expor: `local-read` + `WACLI_GROUP_JID_OPERATIONS`; `min_wacli: "0.18.0"` em `capabilities()`; 103 → 104 condicionado à versão. Não trocar o SQL de `members()` pela CLI, que não traz nomes e custaria um processo por tecla. | médio | horas | `bin/omawhatsapp:176-193`, `224-331`, `3409-3411`, `3741-3777`; `scripts/install:202,371`; `scripts/check-wacli-parity`; skills `wacli-parity.md`/`operations.md`; `docs/PARITY.md:77-79` |
| `--refresh-groups` regrava o roster de todos os grupos | 0.18.0 | adotar: as units já passam a flag. O UNION com `sender_jid` em `members()` vira complemento, e `docs/PARITY.md:77` pode avançar. Risco não verificado: `GetJoinedGroups` sem participantes esvaziaria o roster (fonte do whatsmeow indisponível). | médio | horas | `systemd/user/wacli-sync*.service`; `members()` 2533-2538; `_validated_mentions` |
| diagnósticos do libsignal fora do stdout | 0.18.3 | adotar: parse da última linha JSON (RT-03), que também protege o piso 0.17.1 | médio | horas | `_envelope` 2630-2644; `_transport_result` 3699-3739; `tests/test_backend_hardening.py` |
| `session_revoked` / `SESSION_REVOKED` | 0.18.3 | adotar: `session_ready` e `link_account` (RT-06) e expor `session_revoked` em `report()` para a UI mostrar "sessão encerrada no telefone, vincule de novo" | médio | horas | `session_ready` 3981-3983; `status` 1706-1787; `wacli-sync@.service:12`; `AccountReadiness.qml`; `AccountOperations.qml` |
| cabeçalho de álbum `[Album: N images, M videos]` e corpo de comentários | 0.17.2 | adotar: em `messages()`, omitir ou marcar como `album_header` a linha sem mídia cujo texto case com `^\[Album(: …)?\]$`. Manter o índice privado de álbuns: o wacli não guarda o vínculo pai → filhos e o app envia álbuns como arquivos soltos. | médio | horas | `messages()` 2352-2356, 2452; `App.qml:groupMediaAlbums`; `MessageBubble.qml` |
| áudio sem legenda com `media_caption` vazio | 0.17.2 | adotar: para `media_type=='audio'`, descartar o `[Audio]` legado. A legenda literal na bolha foi deduzida do código, não observada. | baixo | horas | `messages()` 2452-2454; `MessageBubble.qml:40-43,222` |
| `send text --allow-self` | 0.18.0 | expor: política (RT-08) e documentação ("sent: true" não garante entrega; é preciso reiniciar o daemon depois do upgrade) | baixo | horas | skills `wacli-parity.md`/`operations.md`; `capabilities()`; `send()` 2681-2699 |

**Irrelevante ou só observar:**
- Sem código, com ganho automático: edições cifradas decriptadas (0.18.3; aparecem como `edited` na bolha, vale um caso manual em `docs/TESTING.md`); filhos de álbum, menções de status de grupo e convites (`Group invite: X`) indexados; reparo LTHash e replay de recuperação no startup; `chats cleanup` falhando em exclusão parcial (conferir que `App.qml:936` mostra o erro); índices da migração 26, que podem acelerar a subconsulta de `members()`, com menos reescrita de FTS e `stop` atendido durante o reparo de identidades.
- Sem efeito hoje: eventos `offline_sync_preview`/`offline_sync_completed` (as units não usam `--events`); o limite de 2 MiB na waveform (não há waveform armazenada; notas acima de ~131 s enviam a waveform do trecho inicial).
- Só para quem usa o skill: webhooks sem chaves de mídia (0.18.3; citar em `wacli-parity.md:143-146`).
- Sem ação: pares PN/LID na CLI (alias agora gravado nas duas identidades, o que só melhora o `LEFT JOIN contact_aliases`; `_contact_any` segue exigindo JID exato); compatibilidade whatsmeow e tratamento de exclusão de grupo (cobrir no smoke manual).
- Irrelevantes: timestamps UTC de webhook, retry de âncora de backfill, SIGPIPE em JSON, aviso de truncamento de `groups list`, limites de `contacts import-system`, fechamento do container SQLite da sessão, docs do site e mudanças de build/dependências/release.

## 5. Funcionalidades que valem a pena

| # | funcionalidade | suporte (wacli / dados locais) | superfície | valor | esforço | bloqueio/cuidado |
|---|---|---|---|---|---|---|
| 1 | Filtros do rail (Não lidas/Fixadas/Silenciadas) + pasta Arquivadas | `chats.archived,pinned,muted_until,unread_count`, já no payload (`bin/omawhatsapp:2002-2016`); `docs/PARITY.md:37,39` "planned" | App + Dropdown (chips no padrão `App.qml:2399-2416`) | alto | horas | nenhum |
| 2 | Paginação do histórico local | cursor `(ts, rowid)` em `messages()`; hoje o limite é 240 (`Service.qml:918`) e 500 (`bin/omawhatsapp:2355`), sem cursor (`2386-2387`) | App (timeline) | alto | 1 dia | juntar páginas sem quebrar `groupMediaAlbums` nem pular o scroll |
| 3 | Busca global FTS5 com filtros e salto até a mensagem | `messages_fts` (a migração 26 estreita o reindex); `messages search`/`messages context` | App (rail) + skill | alto | 1 dia | escapar a sintaxe MATCH ou delegar a `wacli --read-only messages search --json`; fallback LIKE sem FTS5 |
| 4 | Buscar histórico antigo no celular + mapa de cobertura | `history backfill` (`sync`), `history coverage` (`local-read`); correções 0.17.2 (#371) e 0.18.3 (persistência, #427) | App (fim do timeline) + Configurações + skill | alto | 1 dia | sem delegação, então pausa o sync; best-effort, precisa do celular online; respeitar o modo offline |
| 5 | Nova conversa por contato ou número | `contacts search/show` (local), `contacts check` (remoto), `send text --to` cria a linha em `chats` | App + Dropdown + skill | alto | dias | o gateway resolve `--to` contra o espelho (`WACLI_CHAT_TO_OPERATIONS`), então precisa de um caminho guardado de "primeiro envio" |
| 6 | Tela de favoritas | tabela `starred`, `messages starred` (`local-read`) | App + skill | médio | horas | marcar/desmarcar continua lacuna do wacli (`docs/PARITY.md:122`) |
| 7 | Superfície do agente: `omawhatsapp digest` + folhas/flags 0.18.x | `chats.unread_count` + mensagens recentes; `groups participants list`; política `--allow-self` | skill + `capabilities` | médio | horas | detecção de capacidade por versão |
| 8 | Enviar "digitando…"/"gravando áudio…" | `presence typing/paused` delegados ao socket (as duas versões) | App + Dropdown (opt-in) | médio | horas | debounce de 5-10 s; privacidade; efeito com `--presence-mode quiet` não verificado |
| 9 | Recuperar mídia expirada (`media retry`) | `media retry --chat --limit` (`sync`); `media_unavailable_at` só marca `not_on_phone` | App (MediaBubble) + skill | médio | horas | sem `--id` (pode recuperar outras mídias do chat); pega o lock; celular online |
| 10 | Tiques de entrega/leitura e "digitando" recebido via webhook local | `sync --webhook … --webhook-events receipt,chat_presence --webhook-allow-private` (desde 0.17.1) | App + Dropdown | alto | dias | best-effort e só ao vivo; `chat_presence` exige `--presence-mode normal`; segredo HMAC fora do `ExecStart`. Corrige o `docs/PARITY.md:105,171`, que trata isso como lacuna de transporte. |
| 11 | Painel do grupo (participantes/papéis, convite, ações de admin) | `group_participants` (SQL direto, sem depender de 0.18.0); `groups info/invite/rename/participants …` já classificados | App (painel lateral) | médio | dias | mutações pegam o lock: agrupar sob uma única pausa (padrão `bin/omawhatsapp:1519-1530`); roster pode estar velho |
| 12 | Encaminhar várias mensagens/para vários chats | `messages forward` unitário, não delegado | App | médio | 1 dia | lote sob uma pausa; falha parcial sem reenvio (`OmaWhatsAppPartialError`) |

**Descartadas:**
- Conversa comigo mesmo via `--allow-self`: só texto, entrega não garantida; entra só como política no item 7.
- Ver status/stories: não há `local_path` nem download de mídia de status.
- Marcador de mensagem apagada: correção de paridade barata, fazer junto com o item 2.
- Histórico de chamadas: excluído pelo upstream, `docs/PARITY.md:43`.
- Canais, newsletters e comunidades: fora de escopo.
- Exportar pela UI: o agente já exporta com `private-export`.
- Estatísticas e limpeza da store: valor baixo.
- Enviar localização: sem fonte de coordenadas confiável no desktop.
- Perfil: uso raro.
- Estrela, cartão de contato, prévia de link e timer de mensagens temporárias: continuam lacunas do wacli.

## 6. Plano sugerido em ordem

1. **Portão semver no instalador** (`scripts/install:90-93`): aceitar `>= 0.17.1` e avisar acima de `0.18.3`. Horas.
2. **Versão no helper:** trocar `WACLI_PARITY_VERSION` por `WACLI_MIN_VERSION = "0.17.1"` e `WACLI_TESTED_VERSION = "0.18.3"`. Criar uma sonda `wacli --version` em cache, `min_wacli` por operação no registro e `capabilities()` com a contagem por versão. Ajustar a mensagem de `_transport_path`. Horas.
3. **Registrar `('groups','participants','list')`** como `local-read` em `WACLI_GROUP_JID_OPERATIONS`, com `min_wacli 0.18.0`, e rejeitar por versão antes de chamar o binário. Horas.
4. **`check-wacli-parity` com semântica de piso** e os dois `jq -e` do install (`201-203`, `370-372`) comparando com a contagem calculada. Horas.
5. **Testes e CI:** atualizar `tests/test_backend.py:1216-1226` e `tests/test_backend_hardening.py:793,797`; matriz 0.17.1 + 0.18.3 com sha256 em `.github/workflows/validate.yml`. O sha256 do tarball 0.18.3 ainda precisa ser obtido. Horas.
6. **Teste de contrato de schema** gerado pelos dois binários, rodando os métodos de leitura (reaproveitar `harness.py`), mais `str(exc)` nas mensagens de erro de SQL (SQL-1). 1 dia.
7. **Fallback de daemon antigo** em `_mutate` para `unsupported send kind` e `unsupported send delegate version`, com teste (RT-02). Horas.
8. **Parse da última linha JSON** em `_envelope`/`_transport_result`, com teste (RT-03). Horas.
9. **`session_revoked`** em `session_ready`, `link_account` e `report()` (RT-06). Horas.
10. **`members()`:** `phone` vazio e nome `'WhatsApp member'` para `@lid` (RT-04/SQL-2). Horas.
11. **Política de `--allow-self`** no gateway (RT-08). Horas.
12. **`media download --read-only --output`** com índice `downloaded-media.json`, na UI e no transport. 1 dia.
13. **Timeline:** ocultar `(message)` legado e o cabeçalho `[Album…]` e suprimir o `[Audio]` (SQL-3 e melhorias 0.17.2). Horas.
14. **Heurística de notificação** baseada em `last_message_id`/`unread`, não em `timestamp` (SQL-4). Horas.
15. **Docs:** `README.md`, `docs/PARITY.md` (versão, `--refresh-groups`, recibos delegados, webhooks de recibo), `docs/ARCHITECTURE.md`, `docs/TESTING.md`, `docs/MULTIACCOUNT-SCOPE.md`, skills; downgrade seguro até a migração 26 (SQL-5). Horas.
16. **Funcionalidades em ordem:** 1 (filtros/arquivadas, horas) → 2 (paginação, 1 dia) → 3 (busca FTS5, 1 dia) → 4 (backfill, 1 dia) → 5 (nova conversa, dias) → demais itens da seção 5 conforme demanda.
