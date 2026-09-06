package com.adhdplanner.adhd_planner.wear

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.speech.RecognizerIntent
import android.view.HapticFeedbackConstants
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.ScalingLazyColumnDefaults
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.foundation.rotary.RotaryScrollableDefaults
import androidx.wear.compose.foundation.rotary.rotaryScrollable
import androidx.wear.compose.material3.AppScaffold
import androidx.wear.compose.material3.Button
import androidx.wear.compose.material3.CompactButton
import androidx.wear.compose.material3.FilledTonalButton
import androidx.wear.compose.material3.ListHeader
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.material3.ScreenScaffold
import androidx.wear.compose.material3.Text
import androidx.wear.compose.material3.TimeText
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.delay
import org.json.JSONObject

private val ItemCardShape = RoundedCornerShape(16.dp)

private const val PATH_TOGGLE = "/toggle_item"
private const val PATH_TOGGLE_REST = "/toggle_rest"
private const val PATH_TOGGLE_REST_TOMORROW = "/toggle_rest_tomorrow"
private const val PATH_MOVE_ITEM = "/move_item"
private const val PATH_ADD_MEMO = "/add_memo"

class MainActivity : ComponentActivity(), DataClient.OnDataChangedListener {
    private val data = mutableStateOf(WatchData(emptyList()))
    private val recentMemoSaved = mutableStateOf<String?>(null)

    private val voiceMemoLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            val spokenText = result.data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()
            if (!spokenText.isNullOrBlank()) {
                onAddVoiceMemo(spokenText)
            }
        }
    }

    private fun launchVoiceMemo() {
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ko-KR")
            putExtra(RecognizerIntent.EXTRA_PROMPT, "메모를 말씀하세요")
        }
        try {
            voiceMemoLauncher.launch(intent)
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Voice memo launcher error", e)
        }
    }

    private fun onAddVoiceMemo(text: String) {
        playSuccessVibration(this)
        recentMemoSaved.value = text
        val payload = JSONObject()
            .put("text", text)
            .put("source", "voice")
            .toString()
            .toByteArray()
        sendToPhone(PATH_ADD_MEMO, payload)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        setContent {
            ChecklistScreen(
                data = data.value,
                recentMemoSaved = recentMemoSaved.value,
                onDismissMemoSaved = { recentMemoSaved.value = null },
                onVoiceMemo = ::launchVoiceMemo,
                onToggle = ::onToggle,
                onToggleRest = ::onToggleRest,
                onToggleRestTomorrow = ::onToggleRestTomorrow,
                onMoveItem = ::onMoveItem,
            )
        }
        loadInitial()
    }

    override fun onResume() {
        super.onResume()
        Wearable.getDataClient(this).addListener(this)
        loadInitial()
    }

    override fun onPause() {
        super.onPause()
        Wearable.getDataClient(this).removeListener(this)
    }

    override fun onDataChanged(events: DataEventBuffer) {
        for (event in events) {
            if (event.type == DataEvent.TYPE_CHANGED &&
                event.dataItem.uri.path == PATH_CHECKLIST
            ) {
                try {
                    DataMapItem.fromDataItem(event.dataItem).dataMap
                        .getString("json")
                        ?.let { data.value = ChecklistData.parse(it) }
                } catch (_: Exception) {
                }
            }
        }
    }

    private fun loadInitial() {
        ChecklistData.readLatest(this) { parsed ->
            if (parsed != null) runOnUiThread { data.value = parsed }
        }
    }

    private fun onToggle(segmentId: String, index: Int, checked: Boolean) {
        data.value = data.value.copy(
            blocks = data.value.blocks.map { block ->
                block.copy(
                    items = block.items.map { item ->
                        if (item.segmentId == segmentId && item.index == index) {
                            item.copy(checked = checked)
                        } else {
                            item
                        }
                    },
                )
            },
        )
        val payload = JSONObject()
            .put("segmentId", segmentId)
            .put("index", index)
            .put("checked", checked)
            .toString()
            .toByteArray()
        sendToPhone(PATH_TOGGLE, payload)
    }

    private fun onToggleRest(resting: Boolean) {
        data.value = data.value.copy(restToday = resting)
        sendToPhone(PATH_TOGGLE_REST, resting.toString().toByteArray())
    }

    private fun onToggleRestTomorrow(resting: Boolean) {
        data.value = data.value.copy(restTomorrow = resting)
        sendToPhone(PATH_TOGGLE_REST_TOMORROW, resting.toString().toByteArray())
    }

    private fun onMoveItem(homeSegmentId: String, stepIndex: Int, targetSegmentId: String) {
        val payload = JSONObject()
            .put("homeSegmentId", homeSegmentId)
            .put("stepIndex", stepIndex)
            .put("targetSegmentId", targetSegmentId)
            .toString()
            .toByteArray()
        sendToPhone(PATH_MOVE_ITEM, payload)
    }

    private fun sendToPhone(path: String, payload: ByteArray) {
        Wearable.getNodeClient(this).connectedNodes.addOnSuccessListener { nodes ->
            for (node in nodes) {
                Wearable.getMessageClient(this).sendMessage(node.id, path, payload)
            }
        }
    }
}

fun playCelebrationVibration(context: Context) {
    val timings = longArrayOf(0, 150, 100, 200, 100, 300)
    val amplitudes = intArrayOf(0, 180, 0, 220, 0, 255)
    val effect = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        try {
            VibrationEffect.createWaveform(timings, amplitudes, -1)
        } catch (_: Exception) {
            VibrationEffect.createWaveform(timings, -1)
        }
    } else {
        @Suppress("DEPRECATION")
        VibrationEffect.createWaveform(timings, -1)
    }

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)
            ?.defaultVibrator?.vibrate(effect)
    } else {
        @Suppress("DEPRECATION")
        (context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator)?.vibrate(effect)
    }
}

fun playSuccessVibration(context: Context) {
    val timings = longArrayOf(0, 80, 50, 120)
    val amplitudes = intArrayOf(0, 180, 0, 240)
    val effect = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        try {
            VibrationEffect.createWaveform(timings, amplitudes, -1)
        } catch (_: Exception) {
            VibrationEffect.createWaveform(timings, -1)
        }
    } else {
        @Suppress("DEPRECATION")
        VibrationEffect.createWaveform(timings, -1)
    }

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)
            ?.defaultVibrator?.vibrate(effect)
    } else {
        @Suppress("DEPRECATION")
        (context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator)?.vibrate(effect)
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ChecklistScreen(
    data: WatchData,
    recentMemoSaved: String?,
    onDismissMemoSaved: () -> Unit,
    onVoiceMemo: () -> Unit,
    onToggle: (String, Int, Boolean) -> Unit,
    onToggleRest: (Boolean) -> Unit,
    onToggleRestTomorrow: (Boolean) -> Unit,
    onMoveItem: (String, Int, String) -> Unit,
) {
    val context = LocalContext.current
    val view = LocalView.current
    var movingItem by remember { mutableStateOf<Pair<WatchBlock, WatchItem>?>(null) }
    var celebratingBlock by remember { mutableStateOf<String?>(null) }

    MaterialTheme {
        AppScaffold {
            // 1. 루틴 완료 축하 화면
            if (celebratingBlock != null) {
                BackHandler { celebratingBlock = null }
                val blockName = celebratingBlock!!
                LaunchedEffect(blockName) {
                    playCelebrationVibration(context)
                    delay(3000)
                    if (celebratingBlock == blockName) {
                        celebratingBlock = null
                    }
                }

                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(16.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center,
                    ) {
                        Text(
                            "🎉",
                            style = MaterialTheme.typography.displayMedium,
                            modifier = Modifier.padding(bottom = 4.dp),
                        )
                        Text(
                            "$blockName 완료!",
                            style = MaterialTheme.typography.titleMedium,
                            textAlign = TextAlign.Center,
                            modifier = Modifier.padding(bottom = 6.dp),
                        )
                        Text(
                            "멋져요! 👏\n루틴을 모두 마쳤어요",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center,
                            modifier = Modifier.padding(bottom = 12.dp),
                        )
                        CompactButton(onClick = { celebratingBlock = null }) {
                            Text("확인")
                        }
                    }
                }
            } else if (movingItem != null) {
                // 2. 세부 항목 롱클릭 이동 ("오늘만 여기서") 화면
                BackHandler { movingItem = null }
                val (currentBlock, item) = movingItem!!
                val moveListState = rememberScalingLazyListState()
                val moveFocusRequester = remember { FocusRequester() }
                LaunchedEffect(Unit) {
                    moveFocusRequester.requestFocus()
                }
                ScreenScaffold(
                    scrollState = moveListState,
                    timeText = { TimeText() },
                ) { contentPadding ->
                    ScalingLazyColumn(
                        state = moveListState,
                        contentPadding = contentPadding,
                        scalingParams = ScalingLazyColumnDefaults.scalingParams(
                            edgeScale = 1f,
                            minElementHeight = 0f,
                        ),
                        modifier = Modifier
                            .fillMaxSize()
                            .rotaryScrollable(
                                behavior = RotaryScrollableDefaults.behavior(scrollableState = moveListState),
                                focusRequester = moveFocusRequester,
                            ),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        item(key = "move_title") {
                            Text(
                                text = "\"${item.text}\"\n오늘만 여기서",
                                style = MaterialTheme.typography.titleSmall,
                                textAlign = TextAlign.Center,
                                modifier = Modifier.padding(bottom = 8.dp),
                            )
                        }

                        if (item.isMoved) {
                            item(key = "move_return_home") {
                                Button(
                                    onClick = {
                                        view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                                        onMoveItem(item.segmentId, item.index, item.segmentId)
                                        movingItem = null
                                    },
                                    modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp),
                                ) {
                                    Text("↩ 원래 구간으로 되돌리기", textAlign = TextAlign.Center)
                                }
                            }
                        }

                        val targets = (if (data.allBlocks.isNotEmpty()) data.allBlocks else data.blocks.map {
                            WatchBlockSummary(it.blockId, it.name, it.start, it.end)
                        }).filter { it.blockId != currentBlock.blockId }

                        items(targets, key = { "target_${it.blockId}" }) { target ->
                            FilledTonalButton(
                                onClick = {
                                    view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                                    onMoveItem(item.segmentId, item.index, target.blockId)
                                    movingItem = null
                                },
                                modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp),
                            ) {
                                Text("${target.name}(으)로 이동", textAlign = TextAlign.Center)
                            }
                        }

                        item(key = "move_cancel") {
                            CompactButton(
                                onClick = { movingItem = null },
                                modifier = Modifier.padding(top = 8.dp),
                            ) {
                                Text("취소")
                            }
                        }
                    }
                }
            } else {
                // 3. 메인 체크리스트 화면 (최적화 & 레이아웃 개편)
                var currentMin by remember { mutableStateOf(nowMinute()) }
                LaunchedEffect(Unit) {
                    while (true) {
                        delay(15_000)
                        val now = nowMinute()
                        if (currentMin != now) {
                            currentMin = now
                        }
                    }
                }
                val currentBlocks = remember(data, currentMin) { data.currentBlocks(currentMin) }
                val listState = rememberScalingLazyListState()
                val listFocusRequester = remember { FocusRequester() }
                LaunchedEffect(Unit) {
                    listFocusRequester.requestFocus()
                }

                // 스크롤 렌더링 성능 최적화를 위한 테마 색상 1회 캐싱
                val colorScheme = MaterialTheme.colorScheme
                val checkedBg = colorScheme.surfaceContainerHigh
                val uncheckedBg = colorScheme.surfaceContainer
                val primaryColor = colorScheme.primary
                val outlineColor = colorScheme.outline
                val onSurfaceColor = colorScheme.onSurface
                val onSurfaceCheckedColor = colorScheme.onSurface.copy(alpha = 0.65f)
                val restActiveBg = colorScheme.primaryContainer

                if (recentMemoSaved != null) {
                    LaunchedEffect(recentMemoSaved) {
                        delay(2500)
                        onDismissMemoSaved()
                    }
                }

                ScreenScaffold(
                    scrollState = listState,
                    timeText = { TimeText() },
                ) { contentPadding ->
                    Box(modifier = Modifier.fillMaxSize()) {
                        ScalingLazyColumn(
                            state = listState,
                            contentPadding = contentPadding,
                            autoCentering = null,
                            scalingParams = ScalingLazyColumnDefaults.scalingParams(
                                edgeScale = 1f,
                                minElementHeight = 0f,
                            ),
                            modifier = Modifier
                                .fillMaxSize()
                                .rotaryScrollable(
                                    behavior = RotaryScrollableDefaults.behavior(scrollableState = listState),
                                    focusRequester = listFocusRequester,
                                ),
                        ) {
                            // 바로메모 저장 완료 피드백 (일시적)
                            if (recentMemoSaved != null) {
                                item(key = "memo_saved_card") {
                                    Box(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .padding(top = 16.dp, bottom = 4.dp),
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        Box(
                                            modifier = Modifier
                                                .background(
                                                    color = colorScheme.tertiaryContainer,
                                                    shape = ItemCardShape,
                                                )
                                                .padding(horizontal = 14.dp, vertical = 6.dp),
                                            contentAlignment = Alignment.Center,
                                        ) {
                                            Text(
                                                text = "✓ 메모 저장됨\n\"$recentMemoSaved\"",
                                                style = MaterialTheme.typography.labelSmall,
                                                color = colorScheme.onTertiaryContainer,
                                                textAlign = TextAlign.Center,
                                                maxLines = 2,
                                            )
                                        }
                                    }
                                }
                            }

                            // 바로메모 음성 입력 버튼
                            item(key = "voice_memo_btn") {
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(top = if (recentMemoSaved != null) 2.dp else 16.dp, bottom = 6.dp),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Box(
                                        modifier = Modifier
                                            .background(
                                                color = colorScheme.primaryContainer,
                                                shape = ItemCardShape,
                                            )
                                            .clickable {
                                                view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                                                onVoiceMemo()
                                            }
                                            .padding(horizontal = 16.dp, vertical = 7.dp),
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        Row(
                                            verticalAlignment = Alignment.CenterVertically,
                                            horizontalArrangement = Arrangement.Center,
                                        ) {
                                            Text(
                                                text = "🎤",
                                                style = MaterialTheme.typography.bodySmall,
                                                modifier = Modifier.padding(end = 6.dp),
                                            )
                                            Text(
                                                text = "바로메모",
                                                style = MaterialTheme.typography.labelMedium,
                                                color = colorScheme.onPrimaryContainer,
                                                textAlign = TextAlign.Center,
                                            )
                                        }
                                    }
                                }
                            }

                            // 상단: 쉬는 날 배너 또는 진행 중인 루틴 목록
                            if (data.restToday) {
                                item(key = "rest_today_banner") {
                                    Column(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .padding(top = 16.dp, bottom = 10.dp),
                                        horizontalAlignment = Alignment.CenterHorizontally,
                                    ) {
                                        Text(
                                            "😴",
                                            style = MaterialTheme.typography.displayMedium,
                                            modifier = Modifier.padding(bottom = 6.dp),
                                        )
                                        Text(
                                            "쉬는 날이에요\n푹 쉬어요!",
                                            textAlign = TextAlign.Center,
                                            style = MaterialTheme.typography.titleMedium,
                                        )
                                    }
                                }
                            } else {
                                if (currentBlocks.isEmpty()) {
                                    item(key = "empty_block") {
                                        Column(
                                            modifier = Modifier.fillMaxWidth().padding(vertical = 16.dp),
                                            horizontalAlignment = Alignment.CenterHorizontally,
                                        ) {
                                            Text(
                                                "지금 진행 중인\n구간이 없어요",
                                                textAlign = TextAlign.Center,
                                                style = MaterialTheme.typography.bodyMedium,
                                                modifier = Modifier.padding(bottom = 8.dp),
                                            )
                                            val next = data.nextBlock(currentMin)
                                            if (next != null) {
                                                val timeStr = String.format("%02d:%02d", next.start / 60, next.start % 60)
                                                Text(
                                                    "다음: ${next.name}\n($timeStr 시작)",
                                                    textAlign = TextAlign.Center,
                                                    style = MaterialTheme.typography.labelSmall,
                                                    color = primaryColor,
                                                )
                                            }
                                        }
                                    }
                                } else {
                                    for (block in currentBlocks) {
                                        item(key = "header_${block.blockId}") {
                                            ListHeader { Text(block.name) }
                                        }
                                        items(
                                            items = block.items,
                                            key = { "${block.blockId}_${it.index}" },
                                        ) { item ->
                                            // 가볍고 스크롤과 터치 슬롭 충돌이 없는 네이티브 카드 combinedClickable 구조
                                            Box(
                                                modifier = Modifier
                                                    .fillMaxWidth()
                                                    .padding(vertical = 2.dp)
                                                    .background(
                                                        color = if (item.checked) checkedBg else uncheckedBg,
                                                        shape = ItemCardShape,
                                                    )
                                                    .combinedClickable(
                                                        interactionSource = remember { MutableInteractionSource() },
                                                        indication = null,
                                                        onClick = {
                                                            view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                                                            val nextChecked = !item.checked
                                                            onToggle(item.segmentId, item.index, nextChecked)

                                                            if (nextChecked) {
                                                                val allOthersChecked = block.items
                                                                    .filter { !(it.segmentId == item.segmentId && it.index == item.index) }
                                                                    .all { it.checked }
                                                                if (allOthersChecked && block.items.isNotEmpty()) {
                                                                    celebratingBlock = block.name
                                                                }
                                                            }
                                                        },
                                                        onLongClick = {
                                                            view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                                                            movingItem = block to item
                                                        },
                                                    )
                                                    .padding(horizontal = 14.dp, vertical = 10.dp),
                                            ) {
                                                Row(
                                                    modifier = Modifier.fillMaxWidth(),
                                                    verticalAlignment = Alignment.CenterVertically,
                                                ) {
                                                    Text(
                                                        text = if (item.checked) "✓" else "○",
                                                        style = MaterialTheme.typography.titleMedium,
                                                        color = if (item.checked) primaryColor else outlineColor,
                                                        modifier = Modifier.padding(end = 10.dp),
                                                    )
                                                    val prefix = if (item.isMoved) "📍 " else ""
                                                    Text(
                                                        text = "$prefix${item.text}",
                                                        style = MaterialTheme.typography.bodyMedium,
                                                        color = if (item.checked) onSurfaceCheckedColor else onSurfaceColor,
                                                        textDecoration = if (item.checked) TextDecoration.LineThrough else TextDecoration.None,
                                                        modifier = Modifier.weight(1f),
                                                    )
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // 하단: 쉬는 날 설정 카드 (텍스트 길이에 맞춘 슬림 콤팩트 카드 & 일체형 2dp 간격)
                            item(key = "rest_today_chip") {
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(top = 10.dp, bottom = 2.dp),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Box(
                                        modifier = Modifier
                                            .background(
                                                color = if (data.restToday) restActiveBg else uncheckedBg,
                                                shape = ItemCardShape,
                                            )
                                            .clickable {
                                                view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                                                onToggleRest(!data.restToday)
                                            }
                                            .padding(horizontal = 16.dp, vertical = 7.dp),
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        Text(
                                            text = if (data.restToday) "🌙 오늘 쉬는 날" else "😴 오늘 쉬기",
                                            style = MaterialTheme.typography.bodyMedium,
                                            textAlign = TextAlign.Center,
                                        )
                                    }
                                }
                            }

                            item(key = "rest_tomorrow_chip") {
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(top = 2.dp, bottom = 28.dp),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Box(
                                        modifier = Modifier
                                            .background(
                                                color = if (data.restTomorrow) restActiveBg else uncheckedBg,
                                                shape = ItemCardShape,
                                            )
                                            .clickable {
                                                view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                                                onToggleRestTomorrow(!data.restTomorrow)
                                            }
                                            .padding(horizontal = 16.dp, vertical = 7.dp),
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        Text(
                                            text = if (data.restTomorrow) "🌙 내일 쉬는 날" else "💤 내일 쉬기",
                                            style = MaterialTheme.typography.bodyMedium,
                                            textAlign = TextAlign.Center,
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
