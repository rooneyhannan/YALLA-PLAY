import 'package:flutter/material.dart';

class Song {
  final String title;
  final String artist;
  final String category;
  final bool isPremium;
  final Color coverColor;

  const Song({
    required this.title,
    required this.artist,
    required this.category,
    this.isPremium = false,
    required this.coverColor,
  });
}

final List<Song> dummySongs = [
  // 1. Mandatory First Song (Playable)
  const Song(
    title: "Ba'dak Ala Bali",
    artist: "Fairuz",
    category: "Classic Arab",
    isPremium: false,
    coverColor: Colors.teal,
  ),
  
  // Arab Hits
  const Song(
    title: "Tamally Maak",
    artist: "Amr Diab",
    category: "Arab Pop",
    isPremium: true,
    coverColor: Colors.deepPurple,
  ),
  const Song(
    title: "Nassam Alayna El Hawa",
    artist: "Fairuz",
    category: "Classic Arab",
    isPremium: false,
    coverColor: Colors.indigo,
  ),
  const Song(
    title: "3 Daqat",
    artist: "Abu ft. Yousra",
    category: "Arab Pop",
    isPremium: false,
    coverColor: Colors.blueAccent,
  ),
  const Song(
    title: "C'est La Vie",
    artist: "Cheb Khaled",
    category: "Rai",
    isPremium: true,
    coverColor: Colors.orange,
  ),
  
  // Western Hits
  const Song(
    title: "Shape of You",
    artist: "Ed Sheeran",
    category: "Pop",
    isPremium: true,
    coverColor: Colors.teal,
  ),
  const Song(
    title: "Nothing Else Matters",
    artist: "Metallica",
    category: "Rock",
    isPremium: true,
    coverColor: Colors.black54,
  ),
  const Song(
    title: "Blinding Lights",
    artist: "The Weeknd",
    category: "Synth-pop",
    isPremium: false,
    coverColor: Colors.redAccent,
  ),
  
  // Beginners
  const Song(
    title: "Happy Birthday",
    artist: "Traditional",
    category: "Folk",
    isPremium: false,
    coverColor: Colors.green,
  ),
  const Song(
    title: "Ya Rayah",
    artist: "Rachid Taha",
    category: "Folk",
    isPremium: true,
    coverColor: Colors.deepOrange,
  ),
];
