package com.adhdplanner.adhd_planner.wear

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ChecklistDataTest {
    private val sample = """
        {
          "dateKey": "2026-07-06",
          "blocks": [
            {"blockId":"a","name":"아침","start":600,"end":660,
             "items":[{"segmentId":"a","index":0,"text":"물","checked":true}]},
            {"blockId":"b","name":"밤","start":1320,"end":120,"items":[]}
          ]
        }
    """.trimIndent()

    @Test
    fun `parse reads blocks, times, and items`() {
        val data = ChecklistData.parse(sample)
        assertEquals(2, data.blocks.size)
        val a = data.blocks[0]
        assertEquals("아침", a.name)
        assertEquals(600, a.start)
        assertEquals(660, a.end)
        assertEquals(1, a.items.size)
        assertTrue(a.items[0].checked)
        assertEquals("a", a.items[0].segmentId)
    }

    @Test
    fun `currentBlocks and startingBlocks come from the given minute`() {
        val data = ChecklistData.parse(sample)
        // 10:30 -- inside 아침 (600..660), not 밤.
        assertEquals(listOf("아침"), data.currentBlocks(630).map { it.name })
        // Exactly 10:00 -- 아침 is both current and starting.
        assertEquals(listOf("아침"), data.startingBlocks(600).map { it.name })
        // 10:30 -- nothing STARTS at that minute.
        assertTrue(data.startingBlocks(630).isEmpty())
    }

    @Test
    fun `contains handles a midnight-wrapping block`() {
        val night = ChecklistData.parse(sample).blocks[1] // 22:00 ~ 02:00
        assertTrue(night.contains(23 * 60))
        assertTrue(night.contains(60)) // 01:00
        assertFalse(night.contains(3 * 60))
        // Wrapping block is "current" at 23:00.
        val data = ChecklistData.parse(sample)
        assertEquals(listOf("밤"), data.currentBlocks(23 * 60).map { it.name })
    }

    @Test
    fun `zero-length block contains nothing`() {
        val zero = WatchBlock("z", "빈", 300, 300, emptyList())
        assertFalse(zero.contains(300))
    }

    @Test
    fun `restToday defaults false and parses when present`() {
        assertFalse(ChecklistData.parse(sample).restToday)
        val rest = """{"dateKey":"2026-07-06","restToday":true,"restTomorrow":true,"blocks":[]}"""
        val parsed = ChecklistData.parse(rest)
        assertTrue(parsed.restToday)
        assertTrue(parsed.restTomorrow)
    }

    @Test
    fun `nextBlock picks closest future block`() {
        val json = """
            {
              "dateKey": "2026-07-06",
              "blocks": [],
              "allBlocks": [
                {"blockId":"a","name":"아침","start":540,"end":600},
                {"blockId":"b","name":"점심","start":720,"end":780},
                {"blockId":"c","name":"저녁","start":1140,"end":1200}
              ]
            }
        """.trimIndent()
        val data = ChecklistData.parse(json)
        assertEquals("점심", data.nextBlock(600)?.name)
        assertEquals("저녁", data.nextBlock(800)?.name)
        assertEquals("아침", data.nextBlock(1300)?.name)
    }
}
